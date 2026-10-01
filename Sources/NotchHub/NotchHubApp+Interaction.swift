import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// Hover, click, media transport, and the right-click menu.
extension NotchHubApp {

    // MARK: - Hover & click

    /// Cursor entered the notch region: reveal the island.
    func islandHoverEntered() {
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil
        machine.send(.hoverEntered)
        if petVisible, petSettings.reactions, !petSleepHoverSession {
            petBrain.handle(.hoverEntered, context: petContext(), now: Date())
        }
        renderIsland()
        log("hoverEntered → \(machine.presentation)")
    }

    /// Cursor left the island. The machine holds the shape for its grace
    /// period; the collapse is scheduled for exactly when that ends.
    func islandHoverExited() {
        machine.send(.hoverExited)
        renderIsland()
        log("hoverExited → \(machine.presentation)")

        hoverCollapseTask?.cancel()
        let delay = machine.hoverCollapseDelay + 0.02
        hoverCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, !self.machine.isHovering else { return }
            if self.petSleepHoverSession {
                // The hover Sleep was chosen in is over, even if an activity
                // keeps the island up.
                self.petSleepHoverSession = false
                self.refreshPet()
            }
            self.closePetPanel()
            self.tick()
        }
    }

    /// A click on the notch. It opens the dashboard (a bar with more to show —
    /// a song, a call — grows first), and a click on the open dashboard that
    /// misses its controls closes it again. The song's player is one click away
    /// from the dashboard's "now playing" column or the right-click menu.
    func islandClicked() {
        if panel == .pet {
            closePetPanel()
            return
        }
        machine.send(.clicked)
        renderIsland()
        log("clicked → \(machine.presentation)")
    }

    /// Opens the app an activity came from — for a song, the player that is
    /// actually playing it (a browser tab, Spotify, Music), never a guess based
    /// on which apps happen to be running.
    func openSourceApp(for activity: Activity) {
        guard activity.kind == .music else { return }
        guard let source = activity.sourceBundleID else {
            log("open: player unknown for \"\(activity.title)\"")
            return
        }
        if let browser = MediaBrowsers.browser(bundleID: source) {
            let script = MediaBrowsers.activateMediaTabScript(browser)
            // AppleScript blocks until the browser answers: keep it off main.
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
            }
        } else if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == source }) {
            app.activate(options: [])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }

    // MARK: - Media transport

    /// The transport surface currently on screen, if any. The window
    /// hit-tests clicks against this instead of taking key focus.
    func visibleTransport() -> MediaControlLayout.Placement? {
        guard machine.activity?.kind == .music else { return nil }
        let state = currentIslandState()
        guard state == .expanded else { return nil }
        return MediaControlLayout.placement(
            in: window.localFrame(for: state, content: islandModel.contentSize),
            notchInset: window.notchHeight,
            trailingReserve: petVisible ? PetLayout.expandedReserve : 0
        )
    }

    /// Performs a transport action on the active player via MediaRemote.
    func mediaCommand(_ command: MediaCommand) {
        // Flip the play/pause glyph immediately; the player's next now-playing
        // event confirms the real state.
        if command == .togglePlayPause, let current = queue.current, current.kind == .music {
            var updated = current
            updated.isPlaying.toggle()
            queue.replace(current.id, with: updated)
            renderQueue()
        }
        let dispatched = MediaRemote.send(command)
        log("media: \(command.rawValue) dispatched=\(dispatched)")
    }

    // MARK: - Context menu

    /// Builds the right-click context menu for the current activity.
    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        switch currentActivity?.kind {
        case .music where currentActivity?.sourceBundleID != nil:
            menu.addItem(withTitle: "Open Player", action: #selector(openPlayerAction), keyEquivalent: "")
        case .timer:
            menu.addItem(withTitle: "Stop", action: #selector(stopTimerAction), keyEquivalent: "")
            menu.addItem(withTitle: "Reset", action: #selector(resetTimerAction), keyEquivalent: "")
        default:
            break
        }
        if menu.items.isEmpty {
            menu.addItem(withTitle: "Return to Idle", action: #selector(returnToIdleAction), keyEquivalent: "")
        }

        // The two surfaces with nothing on the island to right-click when they
        // are closed. Named for what the click will DO, so the menu reads the
        // same way whether they are open or not.
        menu.addItem(.separator())
        if featureSettings.isEnabled(.teleprompter) {
            let title = panel == .teleprompter ? "Close Teleprompter" : "Teleprompter…"
            menu.addItem(withTitle: title, action: #selector(toggleTeleprompterAction), keyEquivalent: "")
        }
        if featureSettings.isEnabled(.camera) {
            let title = panel == .camera ? "Close Camera" : "Camera"
            menu.addItem(withTitle: title, action: #selector(toggleCameraAction), keyEquivalent: "")
        }
        // A tick rather than a verb: this one is a STATE people check ("am I
        // hidden right now?"), usually with a call already running.
        let ghost = menu.addItem(withTitle: "Ghost Mode", action: #selector(toggleGhostModeAction), keyEquivalent: "")
        ghost.state = ghostModeEnabled ? .on : .off
        ghost.toolTip = "Hide NotchHub from screen sharing and recordings"

        // With no menu-bar item, these keep Settings and Quit one click away
        // even if another app holds the ⌥⌘, hotkey.
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: "")
        menu.addItem(withTitle: "Quit NotchHub", action: #selector(quitAction), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc func openSettingsAction() {
        toggleSettings()
    }

    @objc func toggleTeleprompterAction() {
        toggleTeleprompter()
    }

    @objc func toggleCameraAction() {
        toggleCamera()
    }

    @objc func toggleGhostModeAction() {
        toggleGhostMode()
    }

    @objc func quitAction() {
        NSApp.terminate(nil)
    }

    @objc func openPlayerAction() {
        if let activity = currentActivity {
            openSourceApp(for: activity)
        }
    }

    /// Stops the running timer; the `timerFinished` event removes its surface.
    @objc func stopTimerAction() {
        timerService.stopTimer()
        log("timer: stopped via context menu")
    }

    /// Restarts the running stopwatch from zero.
    @objc func resetTimerAction() {
        timerService.resetTimer()
        log("timer: reset via context menu")
    }

    @objc func returnToIdleAction() {
        returnToIdle()
    }
}
