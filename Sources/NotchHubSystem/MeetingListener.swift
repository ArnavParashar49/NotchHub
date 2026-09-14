import AppKit
import NotchHubCore

/// Detects a live call, reads its real mute / camera state, and reports both.
///
/// - Zoom, Teams, Webex: a call is the app's in-call helper or the app capturing
///   the microphone (`MeetingDetector`), or its Leave control being on screen.
/// - Google Meet: a meet.google.com call tab in a browser that is capturing the
///   microphone (or was already in this call). When the call's page is visible,
///   its Leave button is the truth — Meet's post-call page keeps the address.
///
/// State comes from the call's own controls through Accessibility
/// (`MeetingAccessibility`); without that permission it is left unknown and
/// the island keeps its own. All work runs off the main thread, one poll at a
/// time, every 2 s.
final class MeetingListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var current: Meeting?
    /// Consecutive polls that found no call while one was showing. A call is
    /// ended only after `missesToEnd`, so a brief gap does not end it.
    private var misses = 0
    private let missesToEnd = 2
    private var inFlight = false
    /// A call the user just left through the island. It is ignored until a
    /// poll no longer sees it, so fading signals never bring it back.
    private var suppressed: String?
    private let queue = DispatchQueue(label: "notchhub.meeting.detect", qos: .utility)

    init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    var name: String { "Meeting" }

    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.poll()
            }
            observers.append(token)
        }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }

    /// The island left this call: forget it now, and keep it hidden until the
    /// call's signals are really gone.
    func noteLeft(_ meeting: Meeting) {
        suppressed = Self.key(meeting)
        current = nil
        misses = 0
        pollSoon()
    }

    /// Reads again shortly (after the island pressed a control).
    func pollSoon(after delay: TimeInterval = 0.45) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.poll()
        }
    }

    // MARK: - Detection

    private func poll() {
        guard !inFlight else { return }
        let apps = NSWorkspace.shared.runningApplications
        var pids: [String: pid_t] = [:]
        for app in apps {
            if let id = app.bundleIdentifier, pids[id] == nil { pids[id] = app.processIdentifier }
        }
        let running = Set(pids.keys)
        let callApps = MeetingApp.allCases.filter { !$0.isBrowserHosted && $0.bundleIDs.contains(where: running.contains) }
        let browsers = BrowserScripting.all.filter { running.contains($0.bundleID) }
        guard !callApps.isEmpty || !browsers.isEmpty else {
            handle(detected: nil)
            return
        }

        inFlight = true
        let currentBrowserID = current?.browserBundleID
        queue.async { [weak self] in
            let found = Self.detect(
                callApps: callApps,
                browsers: browsers,
                running: running,
                pids: pids,
                currentBrowserID: currentBrowserID
            )
            DispatchQueue.main.async {
                self?.inFlight = false
                self?.handle(detected: found)
            }
        }
    }

    /// Runs on `queue`.
    private static func detect(
        callApps: [MeetingApp],
        browsers: [BrowserScripting.Browser],
        running: Set<String>,
        pids: [String: pid_t],
        currentBrowserID: String?
    ) -> Meeting? {
        let inputs = AudioInput.capturingBundleIDs()
        let micInUse = inputs == nil && AudioInput.isInUse()

        if !callApps.isEmpty {
            let heuristic = MeetingDetector.detect(
                runningBundleIDs: running,
                processNames: ProcessTable.names(),
                inputBundleIDs: inputs,
                microphoneInUse: micInUse
            )
            for app in callApps {
                guard let pid = app.bundleIDs.lazy.compactMap({ pids[$0] }).first else { continue }
                let snapshot = MeetingAccessibility.snapshot(pid: pid, app: app, windowTitle: nil)
                guard heuristic == app || snapshot?.leave != nil else { continue }
                var meeting = Meeting(app: app, title: app.name)
                apply(snapshot, to: &meeting)
                return meeting
            }
        }

        for browser in browsers {
            let capturing = MeetingDetector.browserCapturingAudio(browser.bundleID, inputBundleIDs: inputs, microphoneInUse: micInUse)
            guard capturing || currentBrowserID == browser.bundleID else { continue }
            let tabs = BrowserScripting.queue.sync { BrowserScripting.allTabs(of: browser) }
            guard let tab = tabs.first(where: { MeetingLink.googleMeetCall(in: $0.url) != nil }),
                  let call = MeetingLink.googleMeetCall(in: tab.url),
                  let pid = pids[browser.bundleID] else { continue }
            let snapshot = MeetingAccessibility.snapshot(pid: pid, app: .googleMeet, windowTitle: tab.title)
            // With the call's page on screen its Leave button decides;
            // otherwise the microphone does.
            guard snapshot?.inCall ?? capturing else { continue }
            var meeting = Meeting(
                app: .googleMeet,
                title: meetTitle(tab.title),
                browserBundleID: browser.bundleID,
                callURL: call
            )
            apply(snapshot, to: &meeting)
            return meeting
        }
        return nil
    }

    private static func apply(_ snapshot: MeetingAccessibility.Snapshot?, to meeting: inout Meeting) {
        if let muted = snapshot?.isMuted {
            meeting.isMuted = muted
            meeting.knownStates.insert(.mute)
        }
        if let cameraOn = snapshot?.isCameraOn {
            meeting.isCameraOn = cameraOn
            meeting.knownStates.insert(.camera)
        }
    }

    private func handle(detected: Meeting?) {
        if let key = suppressed {
            if let detected, Self.key(detected) == key { return }
            suppressed = nil
        }

        switch (current, detected) {
        case (nil, nil):
            return

        case (nil, let meeting?):
            current = meeting
            misses = 0
            emit(SystemEvent(source: .meeting, payload: .meetingStarted(meeting)))

        case (_?, nil):
            misses += 1
            guard misses >= missesToEnd else { return }
            current = nil
            misses = 0
            emit(SystemEvent(source: .meeting, payload: .meetingEnded))

        case (let existing?, let meeting?):
            misses = 0
            let sameCall = Self.key(existing) == Self.key(meeting)
            let muteChanged = meeting.knownStates.contains(.mute) && meeting.isMuted != existing.isMuted
            let cameraChanged = meeting.knownStates.contains(.camera) && meeting.isCameraOn != existing.isCameraOn
            guard !sameCall || muteChanged || cameraChanged else { return }

            var merged = Meeting(
                app: meeting.app,
                title: meeting.title,
                participantCount: meeting.participantCount,
                startedAt: sameCall ? existing.startedAt : meeting.startedAt,
                isMuted: meeting.knownStates.contains(.mute) ? meeting.isMuted : existing.isMuted,
                isCameraOn: meeting.knownStates.contains(.camera) ? meeting.isCameraOn : existing.isCameraOn,
                isSharing: meeting.isSharing,
                browserBundleID: meeting.browserBundleID,
                callURL: meeting.callURL
            )
            merged.knownStates = meeting.knownStates
            current = merged
            emit(SystemEvent(source: .meeting, payload: .meetingUpdated(merged)))
        }
    }

    static func key(_ meeting: Meeting) -> String {
        "\(meeting.app.rawValue)|\(meeting.callURL ?? "")"
    }

    /// "Meet – xyz-wxyz-xyz" → "xyz-wxyz-xyz"; a named meeting keeps its name.
    static func meetTitle(_ tabTitle: String) -> String {
        var title = tabTitle.trimmingCharacters(in: .whitespaces)
        for prefix in ["Meet – ", "Meet - ", "Meet — "] where title.hasPrefix(prefix) {
            title.removeFirst(prefix.count)
        }
        return title.isEmpty || title == "Meet" ? "Google Meet" : title
    }
}
