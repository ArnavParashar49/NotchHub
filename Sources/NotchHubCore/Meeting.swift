import Foundation

/// A conferencing app the island can drive.
public enum MeetingApp: String, CaseIterable, Codable, Equatable {
    case zoom
    case googleMeet
    case teams
    case webex

    public var name: String {
        switch self {
        case .zoom: return "Zoom"
        case .googleMeet: return "Google Meet"
        case .teams: return "Microsoft Teams"
        case .webex: return "Webex"
        }
    }

    public var symbol: String {
        switch self {
        case .zoom: return "video.fill"
        case .googleMeet: return "video.badge.waveform.fill"
        case .teams: return "person.2.wave.2.fill"
        case .webex: return "video.circle.fill"
        }
    }

    /// Bundle identifiers this app runs as. Google Meet has no app of its own —
    /// it lives in a browser — so it is matched by window title instead.
    public var bundleIDs: [String] {
        switch self {
        case .zoom: return ["us.zoom.xos", "us.zoom.Zoom"]
        case .googleMeet: return []
        case .teams: return ["com.microsoft.teams2", "com.microsoft.teams"]
        case .webex: return ["Cisco-Systems.Spark", "com.webex.meetingmanager", "com.cisco.webexmeetingsapp"]
        }
    }

    /// Substrings that identify this app in a window title or URL.
    public var titleMarkers: [String] {
        switch self {
        case .zoom: return ["Zoom Meeting", "Zoom Webinar", "zoom.us"]
        case .googleMeet: return ["Meet - ", "meet.google.com", "Google Meet"]
        case .teams: return ["Microsoft Teams", "teams.microsoft.com"]
        case .webex: return ["Webex", "webex.com"]
        }
    }

    /// Apps with no dedicated process that appear in a browser instead.
    public var isBrowserHosted: Bool { self == .googleMeet }
}

/// A live call, as the island shows it.
public struct Meeting: Equatable {
    public var app: MeetingApp
    /// The meeting's own name, when it can be read.
    public var title: String
    public var participantCount: Int?
    public let startedAt: Date
    public var isMuted: Bool
    public var isCameraOn: Bool
    public var isSharing: Bool
    /// For a call in a browser tab (Google Meet): the browser running it.
    public var browserBundleID: String?
    /// For a call in a browser tab: the call's address, which finds its tab.
    public var callURL: String?
    /// Which of `isMuted` / `isCameraOn` were read from the call's own
    /// controls. An unread state is a guess and must not overwrite what the
    /// island already shows.
    public var knownStates: Set<MeetingControl> = []

    public init(
        app: MeetingApp,
        title: String,
        participantCount: Int? = nil,
        startedAt: Date = Date(),
        isMuted: Bool = false,
        isCameraOn: Bool = false,
        isSharing: Bool = false,
        browserBundleID: String? = nil,
        callURL: String? = nil
    ) {
        self.app = app
        self.title = title
        self.participantCount = participantCount
        self.startedAt = startedAt
        self.isMuted = isMuted
        self.isCameraOn = isCameraOn
        self.isSharing = isSharing
        self.browserBundleID = browserBundleID
        self.callURL = callURL
    }

    public func elapsed(at now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(startedAt))
    }

    /// `04:12` / `1:02:33` — the call timer.
    public func elapsedLabel(at now: Date = Date()) -> String {
        Activity.format(elapsed(at: now))
    }

    /// `Zoom · 4 in call` — the one-line description under the title.
    public var context: String {
        var parts = [app.name]
        if let participantCount, participantCount > 0 {
            parts.append("\(participantCount) in call")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Call controls

/// A control the island offers during a call.
public enum MeetingControl: String, CaseIterable, Equatable, Sendable {
    case mute
    case camera
    case leave
}

/// A keyboard shortcut expressed as a macOS VIRTUAL key code plus modifiers.
///
/// Virtual key codes are layout positions (`kVK_ANSI_A` is 0x00), not
/// characters — converting a character's ASCII value into a key code sends a
/// completely different key ("a" is 97, which is F6).
public struct KeyChord: Equatable, Sendable {
    public var keyCode: UInt16
    public var command: Bool
    public var shift: Bool

    public init(keyCode: UInt16, command: Bool = true, shift: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
    }

    /// Carbon `kVK_ANSI_*` codes for the letters the call apps use.
    public enum Key {
        public static let a: UInt16 = 0x00
        public static let d: UInt16 = 0x02
        public static let e: UInt16 = 0x0E
        public static let h: UInt16 = 0x04
        public static let m: UInt16 = 0x2E
        public static let o: UInt16 = 0x1F
        public static let v: UInt16 = 0x09
        public static let w: UInt16 = 0x0D
    }
}

public extension MeetingApp {
    /// The app's own documented shortcut for a control, or `nil` when it has
    /// none (the island hides nothing, but sends nothing either).
    ///
    /// - Zoom: ⌘⇧A mute, ⌘⇧V video, ⌘W leave (Zoom confirms before leaving).
    /// - Teams: ⌘⇧M mute, ⌘⇧O camera, ⌘⇧H hang up.
    /// - Google Meet: ⌘D mute, ⌘E camera; leaving has no shortcut.
    func shortcut(for control: MeetingControl) -> KeyChord? {
        switch (self, control) {
        case (.zoom, .mute): return KeyChord(keyCode: KeyChord.Key.a, shift: true)
        case (.zoom, .camera): return KeyChord(keyCode: KeyChord.Key.v, shift: true)
        case (.zoom, .leave): return KeyChord(keyCode: KeyChord.Key.w)
        case (.teams, .mute): return KeyChord(keyCode: KeyChord.Key.m, shift: true)
        case (.teams, .camera): return KeyChord(keyCode: KeyChord.Key.o, shift: true)
        case (.teams, .leave): return KeyChord(keyCode: KeyChord.Key.h, shift: true)
        case (.webex, .mute): return KeyChord(keyCode: KeyChord.Key.m, shift: true)
        case (.webex, .camera): return KeyChord(keyCode: KeyChord.Key.v, shift: true)
        case (.webex, .leave): return nil
        case (.googleMeet, .mute): return KeyChord(keyCode: KeyChord.Key.d)
        case (.googleMeet, .camera): return KeyChord(keyCode: KeyChord.Key.e)
        case (.googleMeet, .leave): return nil
        }
    }

    /// Helper processes that exist ONLY while a call is live. Zoom spawns its
    /// meeting host (`CptHost`, `aomhost` in newer builds) on joining and
    /// quits it on leaving, which makes it the most reliable in-call signal
    /// that needs no permission at all.
    var inCallProcessNames: [String] {
        switch self {
        case .zoom: return ["CptHost", "aomhost"]
        case .teams, .googleMeet, .webex: return []
        }
    }
}

// MARK: - Detection

/// Decides whether a call is actually in progress.
///
/// Merely having Zoom or Teams open is NOT a call — both apps idle in the
/// background for days. A call is signalled by the app's in-call helper
/// process, or by the app itself capturing microphone input.
public enum MeetingDetector {

    /// Whether a browser is capturing the microphone — what separates a Meet
    /// tab that is IN a call from one that is merely open. Browsers capture in
    /// helper processes (`com.google.Chrome.helper`,
    /// `company.thebrowser.browser.helper`), and Safari in WebKit's GPU process.
    public static func browserCapturingAudio(_ browserBundleID: String, inputBundleIDs: Set<String>?, microphoneInUse: Bool) -> Bool {
        guard let inputBundleIDs else { return microphoneInUse }
        let browser = browserBundleID.lowercased()
        return inputBundleIDs.contains { id in
            let id = id.lowercased()
            if id == browser || id.hasPrefix(browser + ".") { return true }
            return browser == "com.apple.safari" && id.hasPrefix("com.apple.webkit.gpu")
        }
    }

    /// - Parameters:
    ///   - runningBundleIDs: bundle identifiers of running GUI apps.
    ///   - processNames: short names (`p_comm`) of every running process.
    ///   - inputBundleIDs: bundle identifiers of processes currently capturing
    ///     audio input, or `nil` when this macOS cannot say (pre-14.2).
    ///   - microphoneInUse: whether any process at all is capturing input — the
    ///     coarse fallback used only when `inputBundleIDs` is `nil`.
    public static func detect(
        runningBundleIDs: Set<String>,
        processNames: Set<String>,
        inputBundleIDs: Set<String>?,
        microphoneInUse: Bool
    ) -> MeetingApp? {
        for app in MeetingApp.allCases where !app.isBrowserHosted {
            guard app.bundleIDs.contains(where: runningBundleIDs.contains) else { continue }

            if app.inCallProcessNames.contains(where: processNames.contains) {
                return app
            }
            if let inputBundleIDs {
                // A helper (e.g. `com.microsoft.teams2.helper`) may own the
                // audio session, so match on the bundle prefix.
                let capturing = inputBundleIDs.contains { id in
                    app.bundleIDs.contains { id == $0 || id.hasPrefix($0 + ".") }
                }
                if capturing { return app }
            } else if microphoneInUse {
                return app
            }
        }
        return nil
    }
}
