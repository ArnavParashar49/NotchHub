import AppKit
import ApplicationServices
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// Live-call controls: mute, camera, leave.
///
/// The island has no API into Zoom or Teams, so each control sends the app's
/// own documented keyboard shortcut (`MeetingApp.shortcut(for:)`). Posting
/// keystrokes to another app requires Accessibility permission; without it the
/// control does nothing and the island's state is left untouched rather than
/// pretending the call changed.
extension NotchHubApp {

    /// Handles a click on a call's controls — the compact bar's mute / leave,
    /// or the expanded panel's row. Returns whether a control was hit.
    func meetingControlHit(at point: NSPoint) -> Bool {
        guard meeting != nil else { return false }
        let state = currentIslandState()
        let control: MeetingControl?
        if state == .meeting {
            let frame = window.localFrame(for: .meeting, content: islandModel.contentSize)
            control = MeetingControlLayout.control(at: point, in: frame, notchInset: window.notchHeight)
        } else if state == .compact, machine.activity?.kind == .meeting {
            let frame = window.localFrame(for: .compact, content: islandModel.contentSize)
            control = MeetingControlLayout.compactControl(at: point, in: frame, inset: DesignTokens.compactInset + petBarReserve)
        } else {
            return false
        }
        guard let control else { return false }
        switch control {
        case .mute: toggleMeetingMute()
        case .camera: toggleMeetingCamera()
        case .leave: leaveMeeting()
        }
        return true
    }

    func toggleMeetingMute() { performMeetingControl(.mute) }

    func toggleMeetingCamera() { performMeetingControl(.camera) }

    func leaveMeeting() { performMeetingControl(.leave) }

    /// Presses the call's own control through Accessibility — its real button,
    /// so the island never guesses the state — and falls back to the app's
    /// keyboard shortcut (or, for a Meet tab, closing the tab to leave).
    func performMeetingControl(_ control: MeetingControl) {
        guard let meeting else { return }
        MeetingControlDriver.press(control, in: meeting) { [weak self] pressed in
            Task { @MainActor in
                guard let self, let current = self.meeting else { return }
                let done = pressed || self.sendShortcut(control, for: current)
                self.log("meeting: \(control.rawValue) pressed=\(pressed) done=\(done)")
                guard done else { return }
                switch control {
                case .mute:
                    // Shown at once; the listener confirms the real state.
                    self.meeting?.isMuted.toggle()
                    self.refreshPanel()
                    self.monitor?.refreshMeeting()
                case .camera:
                    self.meeting?.isCameraOn.toggle()
                    self.refreshPanel()
                    self.monitor?.refreshMeeting()
                case .leave:
                    self.endMeetingLocally(current)
                }
            }
        }
    }

    /// The user left: the call surface goes now, not when the call's signals
    /// eventually fade, and the listener keeps it hidden.
    func endMeetingLocally(_ meeting: Meeting) {
        self.meeting = nil
        queue.remove(kind: .meeting)
        monitor?.meetingLeft(meeting)
        machine.setActivity(nil)
        machine.send(.activityEnded)
        machine.send(.activityEnded)
        renderQueue()
    }

    /// Brings the call app forward and posts its shortcut for `control`.
    /// Returns whether the shortcut was sent.
    @discardableResult
    func sendShortcut(_ control: MeetingControl, for meeting: Meeting) -> Bool {
        // A call in a browser tab (Google Meet): leaving closes the tab
        // (scripting only); mute and camera bring the tab forward and send
        // Meet's own shortcuts.
        if let browserID = meeting.browserBundleID, let url = meeting.callURL {
            if control == .leave {
                BrowserScripting.closeTab(bundleID: browserID, matching: url) { [weak self] ok in
                    Task { @MainActor in self?.log("meeting: closed Meet tab ok=\(ok)") }
                }
                return true
            }
            guard let chord = meeting.app.shortcut(for: control), requestAccessibility(for: "call controls") else {
                return false
            }
            BrowserScripting.focusTab(bundleID: browserID, matching: url) { ok in
                guard ok else { return }
                Task { @MainActor in
                    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == browserID }) else { return }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    NotchHubApp.post(chord, to: app.processIdentifier)
                }
            }
            log("meeting: sent \(control.rawValue) to Google Meet")
            return true
        }

        guard let chord = meeting.app.shortcut(for: control) else {
            log("meeting: \(meeting.app.name) has no \(control.rawValue) shortcut")
            return false
        }
        guard requestAccessibility(for: "call controls") else {
            return false
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { running in
            running.bundleIdentifier.map(meeting.app.bundleIDs.contains) ?? false
        }) else {
            return false
        }

        // The shortcuts act on the call window, so the app must be frontmost;
        // give activation a moment before the keystroke lands.
        app.activate(options: [])
        let pid = app.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.post(chord, to: pid)
        }
        log("meeting: sent \(control.rawValue) to \(meeting.app.name)")
        return true
    }

    static func post(_ chord: KeyChord, to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(chord.keyCode)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        var flags: CGEventFlags = []
        if chord.command { flags.insert(.maskCommand) }
        if chord.shift { flags.insert(.maskShift) }
        down.flags = flags
        up.flags = flags
        down.postToPid(pid)
        up.postToPid(pid)
    }
}
