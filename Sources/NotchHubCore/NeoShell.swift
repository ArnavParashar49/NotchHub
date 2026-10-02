import Foundation

/// NEO.app's menu, carried by NotchHub's Settings.
///
/// While the notch hosts NEO, NEO.app has no menu-bar item: what that menu
/// showed (whether NEO runs, its permissions, Open at Login) and what it did
/// (API keys, logs, restart, erase, quit) live in the NEO section of
/// Settings instead. Everything here is plain values: what NEO's core
/// reported (`NeoShellStatus`), what the section shows for it
/// (`NeoSettingsModel`), what a tap asks for (`NeoSettingsIntent`), and the
/// one command a host may send for it (`NeoShellAction`). Beside the menu,
/// one setting of the core's own: whether NEO listens for "Neo"
/// (`NeoCoreSettings`, and `NeoSetting` to switch it).

/// What NEO.app's own shell reported through the core — the `shell` object of
/// the core's `hello`, and its `shell_status` event. `nil` fields are things
/// nobody reported: a core run by hand has no NEO.app (`app == false`).
public struct NeoShellStatus: Equatable, Sendable {
    /// Whether NEO.app's shell is there to report, and to act.
    public var app: Bool
    public var accessibility: Bool?
    public var screenRecording: Bool?
    public var openAtLogin: Bool?
    public var version: String?
    /// The keys that summon NEO: ⌥⌘ once Accessibility allows it, ⌘⇧Space before.
    public var hotkey: String?

    public init(
        app: Bool = false, accessibility: Bool? = nil, screenRecording: Bool? = nil,
        openAtLogin: Bool? = nil, version: String? = nil, hotkey: String? = nil
    ) {
        self.app = app
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.openAtLogin = openAtLogin
        self.version = version
        self.hotkey = hotkey
    }

    /// From the core's JSON object. `nil` when it is not one of NEO's (an
    /// older core sends none): then nothing is known, which is not the same
    /// as "not allowed".
    public init?(payload: [String: Any]) {
        guard payload["running"] as? Bool == true else { return nil }
        app = payload["app"] as? Bool ?? false
        accessibility = payload["accessibility"] as? Bool
        screenRecording = payload["screen_recording"] as? Bool
        openAtLogin = payload["open_at_login"] as? Bool
        version = (payload["version"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(32)) }
        hotkey = (payload["hotkey"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(16)) }
    }
}

/// One of NEO.app's menu actions, as a host asks the core for it:
/// `{"cmd":"shell","action":…}`. The core takes it only from a host (a
/// native client that said `role=host`), hands it to NEO.app's shell — over
/// the socket NEO.app shares with the core it starts, not through NEO.app's
/// page, which macOS suspends while its window is hidden — and NEO.app runs
/// what its menu item ran. `eraseMemory` erases nothing by itself: NEO.app
/// asks first, in its own dialog.
public enum NeoShellAction: Equatable, Sendable {
    case show
    case settings
    case restart
    case openLogs
    case eraseMemory
    case openAtLogin(Bool)
    case quit

    /// The action's name on the wire.
    public var name: String {
        switch self {
        case .show: return "show"
        case .settings: return "settings"
        case .restart: return "restart"
        case .openLogs: return "open_logs"
        case .eraseMemory: return "erase_memory"
        case .openAtLogin: return "open_at_login"
        case .quit: return "quit"
        }
    }

    /// The command, as one line of JSON.
    public var command: String {
        if case let .openAtLogin(on) = self {
            return #"{"cmd":"shell","action":"\#(name)","on":\#(on)}"#
        }
        return #"{"cmd":"shell","action":"\#(name)"}"#
    }
}

/// What NEO's core said about its own settings — the `wake_word` of its
/// `hello`, and its `settings` event when one is switched. `nil` is a core
/// that did not say (an older one): then nothing is known, and the switch
/// has nothing to show.
public struct NeoCoreSettings: Equatable, Sendable {
    /// "Listen for 'Neo'": the microphone stays on for the wake word (true),
    /// or opens only while NEO is summoned by hand (false).
    public var wakeWord: Bool?

    public init(wakeWord: Bool? = nil) {
        self.wakeWord = wakeWord
    }

    /// From the hello's data, or a `settings` event's. Only a real boolean
    /// counts: `"false"` or `0` is not an answer.
    public init(payload: [String: Any]) {
        wakeWord = Self.bool(payload["wake_word"])
    }

    /// A JSON boolean, and nothing that merely bridges to one (a number).
    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}

/// One of the core's settings, as a host switches it while NEO runs:
/// `{"cmd":"set","name":…,"value":…}`. The core takes it from a host (and
/// from NEO.app's own page) only, keeps it in `~/.neo/.env`, applies it at
/// once and tells every client in a `settings` event — which is what moves
/// the switch here, not the tap.
public enum NeoSetting: Equatable, Sendable {
    /// Listen for "Neo" (on), or keep the microphone closed until NEO is
    /// summoned with its keys (off).
    case wakeWord(Bool)

    /// The setting's name on the wire.
    public var name: String {
        switch self {
        case .wakeWord: return "wake_word"
        }
    }

    /// The command, as one line of JSON.
    public var command: String {
        switch self {
        case let .wakeWord(on): return #"{"cmd":"set","name":"\#(name)","value":\#(on)}"#
        }
    }
}

/// One of the two permissions macOS grants NEO.app.
public enum NeoPermission: String, Equatable, Sendable, CaseIterable {
    case accessibility
    case screenRecording

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    /// Its pane of System Settings › Privacy & Security.
    public var settingsURL: String {
        switch self {
        case .accessibility: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording: return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
    }
}

/// What a tap in the NEO section asks the app for. The view sends these and
/// nothing else; the app decides what each one means (`+NeoSettings`).
public enum NeoSettingsIntent: Equatable, Sendable {
    /// Open NEO's chat in the notch.
    case openChat
    case apiKeys
    case openLogs
    case restart
    case eraseMemory
    case openAtLogin(Bool)
    case quit
    /// Switch "Listen for 'Neo'" to this.
    case wakeWord(Bool)
    /// NEO is not running: launch NEO.app.
    case start
    /// Open the pane of System Settings where the permission is granted.
    case openPermission(NeoPermission)

    /// What the intent asks NEO.app's shell for, or `nil` for the ones the
    /// host does itself (its own panel, launching NEO.app, System Settings).
    public var shellAction: NeoShellAction? {
        switch self {
        case .apiKeys: return .settings
        case .openLogs: return .openLogs
        case .restart: return .restart
        case .eraseMemory: return .eraseMemory
        case let .openAtLogin(on): return .openAtLogin(on)
        case .quit: return .quit
        case .openChat, .start, .openPermission, .wakeWord: return nil
        }
    }

    /// The setting of the core's the intent switches, or `nil` for the rest.
    public var setting: NeoSetting? {
        if case let .wakeWord(on) = self { return .wakeWord(on) }
        return nil
    }
}

/// What the NEO section of Settings shows, from four facts: whether the NEO
/// feature is on, whether NEO's core is connected, what NEO.app's shell last
/// reported, and what the core said about its own settings.
public struct NeoSettingsModel: Equatable, Sendable {

    /// How much of NEO is there to talk to.
    public enum Availability: Equatable, Sendable {
        /// The NEO feature is switched off: NotchHub is not listening for it.
        case off
        /// On, but NEO's core is not connected: NEO is not running.
        case away
        /// The core is connected, but no NEO.app stands behind it (a core run
        /// by hand): the chat works, the menu's actions have nobody to do them.
        case coreOnly
        /// NEO.app and its core: everything works.
        case ready
    }

    public enum PermissionState: Equatable, Sendable {
        case allowed
        case notAllowed
        /// Nobody reported it (NEO is not running, or has no app).
        case unknown

        public var label: String {
            switch self {
            case .allowed: return "Allowed ✓"
            case .notAllowed: return "Not allowed"
            case .unknown: return "—"
            }
        }
    }

    /// NEO's default summon keys, shown until its shell says otherwise.
    public static let defaultHotkey = "⌥⌘"
    /// Where NEO.app is installed.
    public static let appPath = "/Applications/NEO.app"

    public let featureOn: Bool
    public let availability: Availability
    public let accessibility: PermissionState
    public let screenRecording: PermissionState
    /// The Open at Login switch, or `nil` while nobody reported it.
    public let openAtLogin: Bool?
    public let version: String?
    public let hotkey: String
    /// "Listen for 'Neo'" as the core has it, or `nil` while nobody said
    /// (NEO is not running, or its core is too old to have the setting).
    public let wakeWord: Bool?

    public init(featureOn: Bool, connected: Bool, shell: NeoShellStatus?, core: NeoCoreSettings? = nil) {
        self.featureOn = featureOn
        let live = featureOn && connected
        // Like the shell's word: a setting from before NEO quit says nothing now.
        wakeWord = live ? core?.wakeWord : nil
        if !featureOn {
            availability = .off
        } else if !connected {
            availability = .away
        } else if shell?.app == true {
            availability = .ready
        } else {
            availability = .coreOnly
        }
        // What a shell said only counts while its core is connected: a
        // permission from before NEO quit is not a permission now.
        let known = live && shell?.app == true ? shell : nil
        accessibility = Self.state(known?.accessibility)
        screenRecording = Self.state(known?.screenRecording)
        openAtLogin = known?.openAtLogin
        version = known?.version
        hotkey = known?.hotkey ?? Self.defaultHotkey
    }

    private static func state(_ allowed: Bool?) -> PermissionState {
        switch allowed {
        case .some(true): return .allowed
        case .some(false): return .notAllowed
        case .none: return .unknown
        }
    }

    /// Whether NEO's core is connected.
    public var isRunning: Bool { availability == .ready || availability == .coreOnly }

    /// The status row's value.
    public var runningLabel: String {
        switch availability {
        case .off: return "Off in the notch"
        case .away: return "Not running"
        case .coreOnly, .ready: return "Running"
        }
    }

    /// The line under the section's title.
    public var subtitle: String {
        switch availability {
        case .off: return "NEO is off in the notch"
        case .away: return "NEO isn't running"
        case .coreOnly: return "NEO's core is running without NEO.app"
        case .ready: return version.map { "NEO \($0) is running" } ?? "NEO is running"
        }
    }

    /// The quiet line at the foot of the section: why the rows are dim, or
    /// (when nothing is) why NEO's menu is here at all.
    public var footnote: String {
        switch availability {
        case .off: return "Turn NEO on to use these"
        case .away: return "Start NEO to use these"
        case .coreOnly: return "These need NEO.app, not its core alone"
        case .ready: return "NEO's menu lives here while it is in the notch"
        }
    }

    /// The side the "Listen for 'Neo'" switch shows. NEO listens for its name
    /// unless told otherwise, so that is what an unknown value shows (dimmed).
    public var listensForNeo: Bool { wakeWord ?? true }

    /// The line under "Listen for 'Neo'": what the switch's side means for
    /// the microphone — with the keys that summon NEO right now, as its
    /// shell reported them.
    public var wakeWordCaption: String {
        listensForNeo
            ? "The microphone stays on to hear “Neo”."
            : "Summon with \(hotkey) — the microphone is on only while NEO listens."
    }

    /// "Start NEO" shows only when NotchHub is looking for NEO and it is not there.
    public var canStart: Bool { availability == .away }

    public func permission(_ permission: NeoPermission) -> PermissionState {
        switch permission {
        case .accessibility: return accessibility
        case .screenRecording: return screenRecording
        }
    }

    /// Whether a row's control works right now. The chat needs NEO's core,
    /// and so does "Listen for 'Neo'" (a core that has the setting);
    /// the menu's actions need NEO.app behind it; a permission's button shows
    /// only for one NEO.app said it lacks; Start only when NEO is away.
    public func isEnabled(_ intent: NeoSettingsIntent) -> Bool {
        switch intent {
        case .openChat:
            return isRunning
        case .apiKeys, .openLogs, .restart, .eraseMemory, .quit:
            return availability == .ready
        case .openAtLogin:
            return availability == .ready && openAtLogin != nil
        case .wakeWord:
            // The core's own setting: it needs the core (NEO.app or not), and
            // one that said where the switch stands.
            return isRunning && wakeWord != nil
        case .start:
            return canStart
        case let .openPermission(permission):
            return self.permission(permission) == .notAllowed
        }
    }
}
