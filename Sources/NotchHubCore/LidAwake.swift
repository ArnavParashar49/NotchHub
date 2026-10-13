import Foundation

// "Keep working with the lid closed" (Settings → Lid): the pure half.
//
// Closing a MacBook's lid sleeps it whatever power assertions are held
// (`caffeinate` and IOPMAssertions only stop *idle* sleep), unless it is in
// clamshell mode with an external display and power. The one supported switch
// that keeps a closed Mac running is the system setting `pmset -a disablesleep
// 1` (`SleepDisabled 1` in `pmset -g`); `pmset -a disablesleep 0` puts normal
// sleep back. It needs root, so changing it is the controller's job
// (`LidAwakeController`, NotchHubSystem); everything that decides *whether*
// to change it lives here, free of the system, so it can be tested:
//
// - `LidAwakeSettings` — the user's choices, persisted
// - `LidAwakeRecord` — NotchHub's own note that IT turned sleep off, written
//   BEFORE the change, so a crash can always be put right on the next launch
// - `LidAwakePolicy` — the guards: the power adapter, the battery floor, the
//   chosen apps, the auto-off clock
// - `LidAwakeEngine` — the state machine: what to do when the user flips a
//   switch, the power or the apps change, a change finishes, NotchHub
//   launches (crash reconcile) or quits
// - `LidAwakeCommands` · `LidAwakeHelperRule` · `AppleScriptSource` — the
//   exact commands, the sudoers drop-in and the admin-dialog script
// - `LidSettingsModel` · `LidIntent` — what Settings → Lid shows, and its taps

// MARK: - Settings

/// The user's choices for keeping the Mac awake with the lid closed.
public struct LidAwakeSettings: Codable, Equatable, Sendable {
    /// "Keep working with the lid closed".
    public var enabled: Bool
    /// "Only on the power adapter" (default on): on battery the Mac sleeps
    /// as usual. Off, the battery floor applies instead.
    public var onlyOnPower: Bool
    /// With `onlyOnPower` off: at or below this battery level the Mac is let
    /// sleep again (10–50 %, in steps of 5).
    public var batteryFloor: Int
    /// "Only while these apps are open".
    public var onlyWhileApps: Bool
    /// The chosen apps, by bundle identifier (never by name), in the order
    /// they were added.
    public var apps: [String]
    /// "Turn off after": the switch turns itself off this many hours after
    /// it was turned on (or the clock was last changed). `nil` = never.
    public var autoOffHours: Int?
    /// Leave the Mac awake when NotchHub quits (default off: quitting puts
    /// normal sleep back, because nothing would be left to watch the guards).
    public var keepAfterQuit: Bool
    /// When the auto-off clock started: the switch turned on, or the hours
    /// changed while it was on.
    public var clockStart: Date?

    public static let floorRange = 10...50
    public static let floorStep = 5
    public static let defaultFloor = 20
    public static let autoOffChoices = [1, 2, 4, 8]

    public init(
        enabled: Bool = false,
        onlyOnPower: Bool = true,
        batteryFloor: Int = LidAwakeSettings.defaultFloor,
        onlyWhileApps: Bool = false,
        apps: [String] = [],
        autoOffHours: Int? = nil,
        keepAfterQuit: Bool = false,
        clockStart: Date? = nil
    ) {
        self.enabled = enabled
        self.onlyOnPower = onlyOnPower
        self.batteryFloor = Self.clampFloor(batteryFloor)
        self.onlyWhileApps = onlyWhileApps
        self.apps = Self.cleaned(apps)
        self.autoOffHours = Self.validHours(autoOffHours)
        self.keepAfterQuit = keepAfterQuit
        self.clockStart = clockStart
    }

    /// A floor on the 5 % grid, inside 10–50 %.
    public static func clampFloor(_ value: Int) -> Int {
        let stepped = Int((Double(value) / Double(floorStep)).rounded()) * floorStep
        return min(max(stepped, floorRange.lowerBound), floorRange.upperBound)
    }

    /// Only the offered choices; anything else is "never".
    public static func validHours(_ hours: Int?) -> Int? {
        guard let hours, autoOffChoices.contains(hours) else { return nil }
        return hours
    }

    /// Trimmed, non-empty, each once, in order.
    static func cleaned(_ apps: [String]) -> [String] {
        var seen = Set<String>()
        return apps.compactMap { raw in
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return id
        }
    }

    public mutating func addApp(_ bundleID: String) {
        apps = Self.cleaned(apps + [bundleID])
    }

    public mutating func removeApp(_ bundleID: String) {
        apps.removeAll { $0 == bundleID }
    }

    /// When the switch turns itself off, if it is on with a clock.
    public var autoOffDeadline: Date? {
        guard enabled, let hours = autoOffHours, let start = clockStart else { return nil }
        return start.addingTimeInterval(TimeInterval(hours) * 3600)
    }

    // MARK: Codable — every key optional, so an older or newer save decodes.

    private enum CodingKeys: String, CodingKey {
        case enabled, onlyOnPower, batteryFloor, onlyWhileApps, apps, autoOffHours, keepAfterQuit, clockStart
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LidAwakeSettings()
        self.init(
            enabled: (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? defaults.enabled,
            onlyOnPower: (try? c.decodeIfPresent(Bool.self, forKey: .onlyOnPower)) ?? defaults.onlyOnPower,
            batteryFloor: (try? c.decodeIfPresent(Int.self, forKey: .batteryFloor)) ?? defaults.batteryFloor,
            onlyWhileApps: (try? c.decodeIfPresent(Bool.self, forKey: .onlyWhileApps)) ?? defaults.onlyWhileApps,
            apps: (try? c.decodeIfPresent([String].self, forKey: .apps)) ?? defaults.apps,
            autoOffHours: (try? c.decodeIfPresent(Int.self, forKey: .autoOffHours)) ?? nil,
            keepAfterQuit: (try? c.decodeIfPresent(Bool.self, forKey: .keepAfterQuit)) ?? defaults.keepAfterQuit,
            clockStart: (try? c.decodeIfPresent(Date.self, forKey: .clockStart)) ?? nil
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(onlyOnPower, forKey: .onlyOnPower)
        try c.encode(batteryFloor, forKey: .batteryFloor)
        try c.encode(onlyWhileApps, forKey: .onlyWhileApps)
        try c.encode(apps, forKey: .apps)
        try c.encodeIfPresent(autoOffHours, forKey: .autoOffHours)
        try c.encode(keepAfterQuit, forKey: .keepAfterQuit)
        try c.encodeIfPresent(clockStart, forKey: .clockStart)
    }

    // MARK: Persistence

    public static let defaultsKey = "NotchHub.lidAwake"

    public static func load(from defaults: UserDefaults = .standard) -> LidAwakeSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(LidAwakeSettings.self, from: data) else { return LidAwakeSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// NotchHub's own note that it turned sleep off, kept apart from the
/// settings (only the engine writes it). It is written BEFORE the change is
/// made and cleared only once normal sleep is confirmed back, so whatever
/// happens in between — a crash, a kill, a power cut — the next launch knows
/// the `SleepDisabled 1` it finds is NotchHub's to put right.
public struct LidAwakeRecord: Codable, Equatable, Sendable {
    public var ownsSleepDisabled: Bool
    public var since: Date?

    public init(ownsSleepDisabled: Bool = false, since: Date? = nil) {
        self.ownsSleepDisabled = ownsSleepDisabled
        self.since = since
    }

    public static let defaultsKey = "NotchHub.lidAwakeRecord"

    public static func load(from defaults: UserDefaults = .standard) -> LidAwakeRecord {
        guard let data = defaults.data(forKey: defaultsKey),
              let record = try? JSONDecoder().decode(LidAwakeRecord.self, from: data) else { return LidAwakeRecord() }
        return record
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

// MARK: - Power

/// Where the Mac's power comes from, and its battery's charge.
public struct PowerSnapshot: Equatable, Sendable {
    /// On the power adapter (or a UPS): not draining the battery.
    public var onAC: Bool
    /// The internal battery's charge, or `nil` with no battery (a desktop).
    public var batteryPercent: Int?

    public init(onAC: Bool, batteryPercent: Int?) {
        self.onAC = onAC
        self.batteryPercent = batteryPercent
    }
}

// MARK: - Policy

/// Why the Mac is let sleep although the switch is on.
public enum LidAwakeHold: Equatable, Sendable {
    /// "Only on the power adapter", and it is on battery (or its power is
    /// unknown — treated as battery).
    case onBattery
    /// On battery at or below the floor.
    case batteryLow(floor: Int)
    /// The battery floor applies, but the power source or the charge can't
    /// be read: treated as low.
    case powerUnknown
    /// "Only while these apps are open" with no app chosen.
    case noAppsChosen
    /// None of the chosen apps is open.
    case appsClosed
}

/// What the guards say.
public enum LidAwakeVerdict: Equatable, Sendable {
    /// The switch is off.
    case off
    /// The auto-off time has come: the switch turns itself off.
    case expired
    /// On, but a guard lets the Mac sleep for now.
    case held(LidAwakeHold)
    /// Keep the Mac working with the lid closed.
    case awake
}

public enum LidAwakePolicy {
    /// Once the floor has let the Mac sleep on battery, it is not kept awake
    /// again until the charge is this much above the floor (or the adapter is
    /// in), so a reading wobbling across the line cannot flap the setting.
    public static let rearmMargin = 3

    /// The guards, in order: the switch, the clock, the power, the battery,
    /// the apps. `lowLatched` carries the battery floor's hysteresis.
    public static func verdict(
        settings: LidAwakeSettings,
        power: PowerSnapshot?,
        running: Set<String>,
        now: Date,
        lowLatched: Bool
    ) -> (verdict: LidAwakeVerdict, lowLatched: Bool) {
        guard settings.enabled else { return (.off, false) }
        if let deadline = settings.autoOffDeadline, now >= deadline { return (.expired, false) }

        // Unknown power counts as battery: the safe side.
        let onAC = power?.onAC ?? false
        if settings.onlyOnPower {
            if !onAC { return (.held(.onBattery), false) }
        } else if !onAC {
            let floor = settings.batteryFloor
            // On battery (or unknown power) with no charge to compare with the
            // floor: held — the floor cannot be shown to be clear. The latch
            // is kept as the last reading left it.
            guard let percent = power?.batteryPercent else { return (.held(.powerUnknown), lowLatched) }
            let low = percent <= floor || (lowLatched && percent < floor + rearmMargin)
            if low { return (.held(.batteryLow(floor: floor)), true) }
        }

        if settings.onlyWhileApps {
            if settings.apps.isEmpty { return (.held(.noAppsChosen), false) }
            if running.isDisjoint(with: settings.apps) { return (.held(.appsClosed), false) }
        }
        return (.awake, false)
    }
}

// MARK: - Commands

/// The exact commands. Only these two changes are ever made as root:
/// `pmset -a disablesleep 1` and `pmset -a disablesleep 0`.
public enum LidAwakeCommands {
    public static let pmset = "/usr/bin/pmset"
    public static let sudo = "/usr/bin/sudo"
    public static let osascript = "/usr/bin/osascript"

    /// `pmset`'s arguments to set SleepDisabled.
    public static func pmsetArguments(sleepDisabled: Bool) -> [String] {
        ["-a", "disablesleep", sleepDisabled ? "1" : "0"]
    }

    /// The command line as root runs it (and as the helper rule names it).
    public static func pmsetLine(sleepDisabled: Bool) -> String {
        ([pmset] + pmsetArguments(sleepDisabled: sleepDisabled)).joined(separator: " ")
    }

    /// `sudo`'s arguments for the helper path: `-n` never prompts — without
    /// the rule it fails at once instead of waiting on a terminal.
    public static func sudoArguments(sleepDisabled: Bool) -> [String] {
        ["-n", pmset] + pmsetArguments(sleepDisabled: sleepDisabled)
    }

    /// The helper path's command line as a shell runs it: normal sleep back,
    /// never prompting.
    public static var helperRestoreLine: String {
        ([sudo] + sudoArguments(sleepDisabled: false)).joined(separator: " ")
    }

    /// Reading the setting needs no root.
    public static let readArguments = ["-g"]

    /// Asking macOS to sleep needs no root either (the console user may).
    public static let sleepNowArguments = ["sleepnow"]

    /// The dead-man's switch: a `/bin/sh -c` script, started while NotchHub
    /// holds SleepDisabled, that waits for process `pid` to be gone — however
    /// it went: a crash, Force Quit, `kill -9` — and then puts normal sleep
    /// back through the helper (`restore`). NotchHub stops it (SIGTERM) when
    /// it lets go of the setting or quits cleanly, so it fires only when
    /// nothing else could. Ctrl-C and a hang-up of a terminal NotchHub was
    /// started from are ignored, so they cannot take it down with NotchHub.
    ///
    /// If a NotchHub of this user is running again by the time it fires (a
    /// quick relaunch), that one has taken over — its launch reconcile puts
    /// right whatever the record says — and the switch steps aside rather
    /// than undo what the new one just did. `processName` is checked to be a
    /// plain name before it goes into the script; otherwise that check is
    /// left out.
    public static func watchdogScript(pid: Int32, uid: UInt32, processName: String, interval: Double = 5,
                                      restore: String = helperRestoreLine) -> String {
        let seconds = interval == interval.rounded() ? String(Int(interval)) : String(interval)
        var steps = [
            ": notchhub-lid-watchdog",
            "trap '' HUP INT",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep \(seconds); done",
        ]
        if LidAwakeHelperRule.isPlainName(processName) {
            steps.append("/usr/bin/pgrep -q -x -U \(uid) \(processName) && exit 0")
        }
        steps.append("exec \(restore)")
        return steps.joined(separator: "; ")
    }

    /// `SleepDisabled` from `pmset -g`: `true` for 1, `false` for 0 or when
    /// the key is absent (macOS lists it only once it has been set), `nil`
    /// when the text is not `pmset -g`'s at all (the read failed).
    public static func sleepDisabled(inPmsetOutput output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.first == "SleepDisabled" else { continue }
            switch fields.dropFirst().first {
            case "1": return true
            case "0": return false
            default: return nil
            }
        }
        let looksLikePmset = output.contains("System-wide power settings") || output.contains("Currently in use")
        return looksLikePmset ? false : nil
    }
}

/// The helper: a one-line sudoers drop-in that lets this user run exactly
/// the two `pmset` commands without a password.
///
/// Why a drop-in rather than asking every time: the guards must be able to
/// put normal sleep back with nobody at the Mac — unplugged in a bag, the
/// battery at the floor, the chosen apps quit, the clock run out — and an
/// admin dialog waiting behind a closed lid would keep the Mac awake until
/// someone opened it. A privileged helper daemon (SMJobBless / SMAppService)
/// needs a real Developer ID signature, which an ad-hoc-signed NotchHub does
/// not have. So the admin dialog (`AppleScriptSource`, macOS's own password
/// prompt — NotchHub never sees the password) is used to install this rule,
/// and as a fallback only for putting normal sleep BACK.
///
/// Sleep is only ever turned off through the rule itself (`sudo -n pmset -a
/// disablesleep 1`), never through the dialog: that command working proves
/// the same rule will run `… disablesleep 0` with nobody there, so the Mac is
/// never kept awake without a silent way back. (Installing does not turn
/// sleep off in the same dialog for that reason: the rule is checked by use
/// right after it is in place.)
///
/// The rule grants nothing else: no shell, no other `pmset` setting, no
/// wildcard — sudo matches the command and its arguments exactly. The file
/// is validated with `visudo -cf` before it is moved into place (a broken
/// sudoers file would lock the admin out of sudo), owned root:wheel, mode
/// 0440, and named without a dot (sudo skips names that contain one, which
/// is how the temporary copy stays inert while it is checked). Settings →
/// Lid → Remove deletes it.
public struct LidAwakeHelperRule: Equatable, Sendable {
    public static let directory = "/private/etc/sudoers.d"
    public static let fileName = "notchhub-lid"
    public static var path: String { "\(directory)/\(fileName)" }

    public let user: String

    /// `nil` for a name that cannot go into a sudoers rule verbatim (macOS
    /// short names are letters, digits, `_`, `.` and `-`; anything else would
    /// need sudoers escaping, and is refused rather than escaped), and for a
    /// name sudoers would not read as a user: `ALL` (every account) and an
    /// all-capitals name (an alias, which matches no one unless defined).
    public init?(user: String) {
        guard Self.isSafeUserName(user) else { return nil }
        self.user = user
    }

    public static func isSafeUserName(_ name: String) -> Bool {
        guard isPlainName(name), name.count <= 64 else { return false }
        // sudoers reads `[A-Z][A-Z0-9_]*` as a User_Alias, and `ALL` as everyone.
        let alias = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        let first = name.unicodeScalars.first!
        let looksLikeAlias = CharacterSet.uppercaseLetters.contains(first) && first.isASCII
            && name.unicodeScalars.allSatisfy { alias.contains($0) }
        return !looksLikeAlias
    }

    /// Letters, digits, `_`, `.` and `-`, not starting with `.` or `-`.
    public static func isPlainName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        let leading = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        return leading.contains(first) && name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// The rule, exactly.
    public var line: String {
        "\(user) ALL=(root) NOPASSWD: \(LidAwakeCommands.pmsetLine(sleepDisabled: false)), \(LidAwakeCommands.pmsetLine(sleepDisabled: true))"
    }

    /// The file's content.
    public var content: String { line + "\n" }

    /// The shell script root runs (through the admin dialog) to install the
    /// rule — and nothing else: sleep is then turned off through the rule.
    /// One line (`;`-joined): no here-doc, no line endings to translate.
    public func installScript() -> String {
        let dir = Self.directory
        let steps = [
            "set -e",
            "umask 077",
            "/bin/mkdir -p \(dir)",
            // A dot in the name: sudo ignores the file while it is checked.
            "t=$(/usr/bin/mktemp \(dir)/.\(Self.fileName).XXXXXX)",
            "trap '/bin/rm -f \"$t\"' EXIT",
            "/usr/bin/printf '%s\\n' '\(line)' > \"$t\"",
            "/usr/sbin/visudo -cf \"$t\" >/dev/null",
            "/usr/sbin/chown root:wheel \"$t\"",
            "/bin/chmod 0440 \"$t\"",
            "/bin/mv -f \"$t\" \(Self.path)",
            // The whole policy still parses with it in place, or it goes.
            "/usr/sbin/visudo -c >/dev/null || { /bin/rm -f \(Self.path); exit 1; }",
        ]
        return steps.joined(separator: "; ")
    }

    /// Removes the rule, putting normal sleep back first when asked.
    public static func uninstallScript(thenSleepDisabled: Bool? = nil) -> String {
        var steps: [String] = []
        if let value = thenSleepDisabled {
            steps.append(LidAwakeCommands.pmsetLine(sleepDisabled: value))
        }
        steps.append("/bin/rm -f \(path)")
        return steps.joined(separator: "; ")
    }
}

/// The admin dialog: AppleScript's `do shell script … with administrator
/// privileges`, run by `osascript`. macOS shows its own password prompt and
/// runs the script as root; NotchHub only hears whether it worked.
public enum AppleScriptSource {
    /// A string literal: backslashes and double quotes escaped, in that order.
    public static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public static func adminShellScript(_ script: String, prompt: String) -> String {
        "do shell script \(quoted(script)) with prompt \(quoted(prompt)) with administrator privileges"
    }

    /// AppleScript's "User canceled." (error -128), as `osascript` prints it.
    public static func isUserCancel(_ stderr: String) -> Bool {
        stderr.contains("(-128)") || stderr.localizedCaseInsensitiveContains("user canceled")
    }
}

// MARK: - Engine

/// What the engine asks the controller to do.
public enum LidAwakeEffect: Equatable, Sendable {
    /// Set SleepDisabled with the helper rule (`sudo -n`). When `interactive`
    /// — only ever for putting normal sleep BACK — the admin dialog is the
    /// fallback if the rule is missing or refused (and the controller still
    /// never shows it to a closed lid nobody asked from). Sleep is never
    /// turned off through the dialog.
    case apply(sleepDisabled: Bool, interactive: Bool)
    /// Install the helper rule (one admin dialog). Nothing else: whatever
    /// comes next goes through the rule, which checks it.
    case installHelper
    /// Remove the helper rule (one admin dialog), putting normal sleep back
    /// in the same dialog when given.
    case removeHelper(thenSleepDisabled: Bool?)
    case saveSettings
    case saveRecord
    /// The guards just put normal sleep back: if the lid is closed with no
    /// external display, make sure the Mac does go to sleep.
    case nudgeSleep

    /// The SleepDisabled value the effect sets, if it sets one.
    public var target: Bool? {
        switch self {
        case let .apply(value, _): return value
        case let .removeHelper(value): return value
        case .installHelper, .saveSettings, .saveRecord, .nudgeSleep: return nil
        }
    }

    /// Whether the effect runs a command (and so must finish before the next).
    public var runsCommand: Bool {
        switch self {
        case .apply, .installHelper, .removeHelper: return true
        case .saveSettings, .saveRecord, .nudgeSleep: return false
        }
    }
}

/// How a command went.
public enum LidAwakeOutcome: Equatable, Sendable {
    case done
    /// The admin dialog was cancelled.
    case cancelled
    case failed(String)
}

/// The last thing worth telling the user about.
public enum LidAwakeNote: Equatable, Sendable {
    /// The auto-off clock ran out.
    case timeUp(hours: Int)
    /// The admin dialog was cancelled.
    case cancelled
    /// The change failed.
    case failed(String)
}

/// Who asked, which decides what may be shown a password dialog.
///
/// - Turning sleep OFF never shows one, whoever asks: it goes through the
///   helper rule or not at all. Only the person flipping the switch (or
///   tapping Resume / Set Up) may be asked to install the rule.
/// - Putting sleep BACK may show one as a fallback when the rule fails: for
///   a person at the page any time; for the guards acting on their own at
///   most once per hold, and never to a closed lid — otherwise the rule is
///   retried, silently, on every later fact and every minute.
public enum LidAwakeCause: Equatable, Sendable {
    /// The main switch, Resume, Set Up, Remove, Restore normal sleep.
    case user
    /// Any other row on the page: someone is there, but did not ask to be
    /// prompted to keep the Mac awake.
    case settings
    /// The guards on their own: the power, the apps, the clock, a wake.
    case automatic
    /// NotchHub starting (the crash reconcile).
    case launch
}

/// The state machine. Pure: it is fed facts (the settings, the power, the
/// running apps, what `pmset -g` says, whether the helper is installed) and
/// answers with effects, which the controller carries out and reports back
/// (`finished`). One command at a time; anything that changes while one is
/// in flight is looked at again when it finishes.
///
/// The Mac is kept awake only while there is a silent way back: NotchHub
/// turns sleep off through the helper rule alone (which proves the rule
/// works), checks the rule again at launch and now and then while it holds
/// the setting (`probe`: re-asserting the value already set), and puts normal
/// sleep back as soon as the rule stops working.
public struct LidAwakeEngine: Equatable, Sendable {

    /// The command in flight, and who asked for it.
    public struct InFlight: Equatable, Sendable {
        public var effect: LidAwakeEffect
        public var cause: LidAwakeCause
        /// The person turning the switch on: a "no" or a failure turns it
        /// back off.
        public var turningOn: Bool
        /// A check of the helper that re-asserts the value already set: it
        /// changes nothing, so the page does not show it.
        public var probe: Bool
        /// The record as it was before the command, for a failure whose
        /// result could not be read back.
        public var recordBefore: LidAwakeRecord
        /// SleepDisabled as it was believed before the command.
        public var sleepDisabledBefore: Bool
    }

    /// How often, at most, a fresh read (a wake, the page opening) re-checks
    /// the helper while the switch is on.
    public static let probeInterval: TimeInterval = 600

    public private(set) var settings: LidAwakeSettings
    public private(set) var record: LidAwakeRecord
    public private(set) var power: PowerSnapshot?
    public private(set) var running: Set<String>
    /// SleepDisabled as last read (or as the last successful change left
    /// it); `nil` = not known.
    public private(set) var observed: Bool?
    public private(set) var helperInstalled: Bool
    /// The helper rule is installed but `sudo -n` refused it.
    public private(set) var helperRefused = false
    public private(set) var inFlight: InFlight?
    /// The guards want the Mac awake, but that needs the person (the helper
    /// is missing or refused, or the last change didn't take): "Resume" asks.
    public private(set) var needsYou = false
    /// The admin dialog to put normal sleep back has been shown in this hold
    /// (answered, cancelled or timed out): the guards don't show it again on
    /// their own — they keep retrying the helper, silently.
    public private(set) var restorePromptShown = false
    public private(set) var note: LidAwakeNote?
    public private(set) var verdict: LidAwakeVerdict = .off
    /// `launch` has run: until then nothing is changed (an inspection
    /// launch never starts the controller).
    public private(set) var started = false
    /// When `sudo -n` was last tried, worked or not.
    public private(set) var probedAt: Date?
    private var lowLatched = false

    public init(settings: LidAwakeSettings, record: LidAwakeRecord, helperInstalled: Bool,
                power: PowerSnapshot? = nil, running: Set<String> = []) {
        self.settings = settings
        self.record = record
        self.helperInstalled = helperInstalled
        self.power = power
        self.running = running
    }

    public var busy: Bool { inFlight != nil }

    /// The Mac's sleep as far as is known: what `pmset -g` said, or failing
    /// that what NotchHub's record says it did.
    public var sleepDisabled: Bool { observed ?? record.ownsSleepDisabled }

    /// NotchHub is keeping the Mac awake right now.
    public var isKeepingAwake: Bool { record.ownsSleepDisabled && sleepDisabled }

    /// The helper rule is there and `sudo -n` has not refused it.
    public var helperUsable: Bool { helperInstalled && !helperRefused }

    /// NotchHub's SleepDisabled 1 should be put back and is not yet (a
    /// restore failed, or is due): the controller retries on a timer.
    public var restorePending: Bool {
        record.ownsSleepDisabled && sleepDisabled && !(verdict == .awake && helperUsable)
    }

    // MARK: Launch — the crash reconcile

    /// NotchHub has started: compare what `pmset -g` says with the record and
    /// the guards, and put it right.
    ///
    /// - SleepDisabled 0 but the record says NotchHub turned it off: the
    ///   record is stale (the change never landed, or someone put it back) —
    ///   cleared.
    /// - SleepDisabled 1, the record NotchHub's, and the switch off, a guard
    ///   holding or the helper not working: normal sleep is put back (the
    ///   admin dialog may show if the helper cannot do it and the lid is
    ///   open — this is the crash case: safety first).
    /// - SleepDisabled 1 and NOT NotchHub's (set by hand, or by another app):
    ///   left alone and said so on the page, with a button to restore it —
    ///   unless the switch is on and the guards pass, when it is adopted
    ///   through the helper.
    /// - The switch on: the helper is checked (by use), and the Mac kept or
    ///   turned awake through it — never a password prompt to keep it awake.
    public mutating func launch(observed: Bool?, power: PowerSnapshot?, running: Set<String>,
                                helperInstalled: Bool, now: Date) -> [LidAwakeEffect] {
        started = true
        self.observed = observed
        self.power = power
        self.running = running
        self.helperInstalled = helperInstalled
        var effects: [LidAwakeEffect] = []
        if observed == false, record.ownsSleepDisabled {
            record = LidAwakeRecord()
            effects.append(.saveRecord)
        }
        return effects + evaluate(now: now, cause: .launch, probe: settings.enabled)
    }

    // MARK: Facts

    public mutating func update(power: PowerSnapshot?, now: Date) -> [LidAwakeEffect] {
        guard power != self.power else { return [] }
        self.power = power
        return evaluate(now: now, cause: .automatic)
    }

    public mutating func update(running: Set<String>, now: Date) -> [LidAwakeEffect] {
        guard running != self.running else { return [] }
        self.running = running
        return evaluate(now: now, cause: .automatic)
    }

    /// A fresh `pmset -g` and helper check (on wake, or the page opening).
    /// While the switch is on, the helper is re-checked if it has not been
    /// for `probeInterval`.
    public mutating func update(observed: Bool?, helperInstalled: Bool, now: Date) -> [LidAwakeEffect] {
        guard !busy else { return [] }
        var effects: [LidAwakeEffect] = []
        if let observed { self.observed = observed }
        if helperInstalled != self.helperInstalled {
            self.helperInstalled = helperInstalled
            helperRefused = false
        }
        if observed == false, record.ownsSleepDisabled {
            // Normal sleep was put back behind NotchHub's back.
            record = LidAwakeRecord()
            effects.append(.saveRecord)
        }
        let due = probedAt.map { now.timeIntervalSince($0) >= Self.probeInterval } ?? true
        return effects + evaluate(now: now, cause: .automatic, probe: settings.enabled && due)
    }

    /// The clock moved on: the auto-off deadline, or the minute between
    /// retries of a restore that has not landed.
    public mutating func tick(now: Date) -> [LidAwakeEffect] {
        evaluate(now: now, cause: .automatic)
    }

    // MARK: The user

    /// "Keep working with the lid closed".
    public mutating func setEnabled(_ on: Bool, now: Date) -> [LidAwakeEffect] {
        var effects: [LidAwakeEffect] = []
        if on != settings.enabled {
            settings.enabled = on
            settings.clockStart = on ? now : nil
            effects.append(.saveSettings)
        }
        note = nil
        needsYou = false
        restorePromptShown = false
        return effects + evaluate(now: now, cause: .user, turningOn: on)
    }

    /// Any other setting on the page. Someone is there — so putting normal
    /// sleep back may ask for the password — but they did not ask to be
    /// prompted to keep the Mac awake: that goes through the helper or waits
    /// for Resume.
    public mutating func change(now: Date, _ edit: (inout LidAwakeSettings) -> Void) -> [LidAwakeEffect] {
        var next = settings
        edit(&next)
        // Re-validated; the switch itself only moves through `setEnabled`.
        next = LidAwakeSettings(
            enabled: settings.enabled, onlyOnPower: next.onlyOnPower, batteryFloor: next.batteryFloor,
            onlyWhileApps: next.onlyWhileApps, apps: next.apps, autoOffHours: next.autoOffHours,
            keepAfterQuit: next.keepAfterQuit, clockStart: settings.clockStart
        )
        // A new clock starts now, rather than from when the switch went on
        // (four hours chosen five hours in would end it on the spot).
        if next.autoOffHours != settings.autoOffHours {
            next.clockStart = settings.enabled ? now : nil
        }
        guard next != settings else { return [] }
        settings = next
        return [.saveSettings] + evaluate(now: now, cause: .settings)
    }

    /// "Resume": the guards want the Mac awake and it needs the person.
    public mutating func resume(now: Date) -> [LidAwakeEffect] {
        needsYou = false
        return evaluate(now: now, cause: .user)
    }

    /// "Restore normal sleep": SleepDisabled back to 0, whoever set it.
    public mutating func restoreNormalSleep(now: Date) -> [LidAwakeEffect] {
        guard !busy else { return [] }
        var effects: [LidAwakeEffect] = []
        if settings.enabled {
            settings.enabled = false
            settings.clockStart = nil
            effects.append(.saveSettings)
        }
        note = nil
        needsYou = false
        verdict = .off
        return effects + run(.apply(sleepDisabled: false, interactive: true), cause: .user, now: now)
    }

    /// "Set up": install the helper rule — then check it by use, turning
    /// sleep off through it when the guards want the Mac awake now.
    public mutating func installHelper(now: Date) -> [LidAwakeEffect] {
        guard !busy else { return [] }
        note = nil
        return run(.installHelper, cause: .user, now: now)
    }

    /// "Remove": delete the helper rule. Without it the guards could no
    /// longer put sleep back on their own, so once it is gone the switch is
    /// off — and normal sleep goes back in the same dialog.
    public mutating func removeHelper(now: Date) -> [LidAwakeEffect] {
        guard !busy else { return [] }
        note = nil
        needsYou = false
        let restore = record.ownsSleepDisabled && sleepDisabled
        return run(.removeHelper(thenSleepDisabled: restore ? false : nil), cause: .user, now: now)
    }

    // MARK: A command finished

    /// The controller ran the command in flight.
    /// - Parameters:
    ///   - observed: a fresh `pmset -g` (`nil` if the read failed)
    ///   - helperInstalled: whether the rule's file is there now
    ///   - helperWorked: `sudo -n` was tried and worked (`true`), was tried
    ///     and refused (`false`), or was not tried (`nil`)
    ///   - askedAdmin: the admin dialog was shown to put sleep back
    public mutating func finished(outcome: LidAwakeOutcome, observed: Bool?, helperInstalled: Bool,
                                  helperWorked: Bool?, askedAdmin: Bool = false, now: Date) -> [LidAwakeEffect] {
        guard let flight = inFlight else { return [] }
        inFlight = nil
        let effect = flight.effect
        let target = effect.target
        var outcome = outcome
        // A command that "worked" but left `pmset -g` saying otherwise did
        // not work: treated as a failure, so nothing retries it in a loop.
        if outcome == .done, let target, let observed, observed != target {
            outcome = .failed("macOS kept SleepDisabled at \(observed ? 1 : 0)")
        }

        self.helperInstalled = helperInstalled
        if !helperInstalled {
            helperRefused = false
        } else if effect == .installHelper, outcome == .done {
            helperRefused = false
        } else if let helperWorked {
            helperRefused = !helperWorked
        }
        if helperWorked != nil { probedAt = now }

        if let observed {
            self.observed = observed
        } else if outcome == .done, let target {
            self.observed = target
        }

        var effects: [LidAwakeEffect] = []
        // The record follows the system: NotchHub owns a SleepDisabled 1 it
        // set, and nothing once it is 0. A failed command changed nothing it
        // can be sure of: a SleepDisabled 1 that was there before stays as it
        // was recorded (an outside one is not adopted by a failed adoption).
        let before = record
        if observed == nil, outcome != .done {
            record = flight.recordBefore
        } else if !sleepDisabled {
            record = LidAwakeRecord()
        } else if outcome != .done, flight.sleepDisabledBefore {
            record = flight.recordBefore
        }
        if record != before { effects.append(.saveRecord) }
        if askedAdmin, target == false { restorePromptShown = true }

        switch outcome {
        case .done:
            if target == true {
                needsYou = false
                if !flight.probe { note = nil }
            } else if !isTimeUp, !flight.probe {
                note = nil
            }
            // Normal sleep is back: this hold is over.
            if target == false, !sleepDisabled { restorePromptShown = false }
            if case .removeHelper = effect, settings.enabled {
                settings.enabled = false
                settings.clockStart = nil
                effects.append(.saveSettings)
            }
            // The guards put sleep back: make sure a closed Mac does sleep.
            if target == false, flight.cause != .user, !flight.probe, !sleepDisabled {
                effects.append(.nudgeSleep)
            }
        case .cancelled, .failed:
            // A background check of the helper says so on the helper's row,
            // not as a failure of something the person did.
            if !flight.probe || flight.turningOn {
                if case let .failed(why) = outcome { note = .failed(why) } else { note = .cancelled }
            }
            if flight.turningOn, settings.enabled, !sleepDisabled {
                // The person turning it on said no (or it failed): the
                // switch goes back off rather than sit on, doing nothing.
                settings.enabled = false
                settings.clockStart = nil
                effects.append(.saveSettings)
            } else if target == true, !flight.probe {
                needsYou = settings.enabled
            }
        }

        // Anything that changed while the command ran. After an install the
        // person is still there: the rule is checked by use right away. After
        // a failed restore, the next try waits for the next fact or the
        // controller's retry clock — never straight back into a loop.
        if effect == .installHelper, outcome == .done, flight.cause == .user {
            return effects + evaluate(now: now, cause: .settings, turningOn: flight.turningOn, probe: true)
        }
        let restoreFailed = target == false && outcome != .done && !flight.probe
        return effects + evaluate(now: now, cause: .automatic, restoreNow: !restoreFailed)
    }

    // MARK: Quit

    /// Whether NotchHub going away must put normal sleep back — at quit, and
    /// (the controller's dead-man's switch) after a crash: NotchHub turned it
    /// off (or is turning it off: the record is written first), and "Keep
    /// after NotchHub quits" is off, or the guards no longer want the Mac
    /// awake, or there is no working helper. Not the cached `observed`: a
    /// command in flight may have changed it since.
    public func shouldRestoreOnQuit(now: Date) -> Bool {
        guard record.ownsSleepDisabled else { return false }
        var copy = self
        copy.refreshVerdict(now: now)
        return !(settings.keepAfterQuit && copy.verdict == .awake && helperUsable)
    }

    /// The quit restore ran (synchronously); `observed` is a fresh read.
    public mutating func quitRestored(outcome: LidAwakeOutcome, observed: Bool?) -> [LidAwakeEffect] {
        inFlight = nil
        if let observed {
            self.observed = observed
        } else if outcome == .done {
            self.observed = false
        }
        guard !sleepDisabled, record.ownsSleepDisabled else { return [] }
        record = LidAwakeRecord()
        return [.saveRecord]
    }

    // MARK: Evaluation

    private var isTimeUp: Bool {
        if case .timeUp = note { return true }
        return false
    }

    private mutating func refreshVerdict(now: Date) {
        let result = LidAwakePolicy.verdict(settings: settings, power: power, running: running, now: now, lowLatched: lowLatched)
        verdict = result.verdict
        lowLatched = result.lowLatched
    }

    private mutating func markOwned(now: Date) -> [LidAwakeEffect] {
        guard !record.ownsSleepDisabled else { return [] }
        record = LidAwakeRecord(ownsSleepDisabled: true, since: now)
        return [.saveRecord]
    }

    /// Starts a command. One that turns sleep off writes the record FIRST, so
    /// a crash between the two is put right (by the dead-man's switch, or on
    /// the next launch — a record with SleepDisabled 0 is simply cleared).
    private mutating func run(_ effect: LidAwakeEffect, cause: LidAwakeCause, turningOn: Bool = false,
                              probe: Bool = false, now: Date) -> [LidAwakeEffect] {
        let before = record
        let sleepBefore = sleepDisabled
        var effects: [LidAwakeEffect] = []
        if effect.target == true { effects += markOwned(now: now) }
        inFlight = InFlight(effect: effect, cause: cause, turningOn: turningOn, probe: probe,
                            recordBefore: before, sleepDisabledBefore: sleepBefore)
        return effects + [effect]
    }

    /// - Parameters:
    ///   - probe: also check the helper (by re-asserting the value already
    ///     set) when nothing else would run a command through it
    ///   - restoreNow: `false` right after a restore failed, so the guards
    ///     wait for the next fact before trying again
    private mutating func evaluate(now: Date, cause: LidAwakeCause, turningOn: Bool = false,
                                   probe: Bool = false, restoreNow: Bool = true) -> [LidAwakeEffect] {
        refreshVerdict(now: now)
        var effects: [LidAwakeEffect] = []
        if verdict == .expired {
            note = .timeUp(hours: settings.autoOffHours ?? 0)
            settings.enabled = false
            settings.clockStart = nil
            verdict = .off
            effects.append(.saveSettings)
        }
        if verdict != .awake { needsYou = false }
        guard started, inFlight == nil else { return effects }

        if verdict == .awake {
            if helperUsable {
                // Not a hold (or one just over): a later one may ask once.
                restorePromptShown = false
                if sleepDisabled {
                    needsYou = false
                    // An outside SleepDisabled 1 with the switch on is adopted
                    // — through the helper, which proves the way back; NotchHub's
                    // own is re-asserted when the helper is due a check.
                    if !record.ownsSleepDisabled || probe {
                        return effects + run(.apply(sleepDisabled: true, interactive: false), cause: cause,
                                             turningOn: turningOn, probe: record.ownsSleepDisabled, now: now)
                    }
                    return effects
                }
                // After a change that didn't take, the guards wait for a person.
                if needsYou, cause == .automatic || cause == .launch { return effects }
                return effects + run(.apply(sleepDisabled: true, interactive: false), cause: cause,
                                     turningOn: turningOn, now: now)
            }
            // No working helper. The person flipping the switch (or Resume)
            // is asked to set it up; the guards and the other rows wait.
            if cause == .user {
                return effects + run(.installHelper, cause: cause, turningOn: turningOn, now: now)
            }
            needsYou = true
            // …and a SleepDisabled 1 of NotchHub's with no silent way back is
            // not kept: it goes back below.
        }

        // The switch is off, a guard holds, or there is no working helper:
        // normal sleep goes back — but only a SleepDisabled NotchHub set.
        if record.ownsSleepDisabled, sleepDisabled {
            switch cause {
            case .user, .settings:
                return effects + run(.apply(sleepDisabled: false, interactive: true), cause: cause, now: now)
            case .automatic, .launch:
                guard restoreNow else { return effects }
                return effects + run(.apply(sleepDisabled: false, interactive: !restorePromptShown), cause: cause, now: now)
            }
        }

        // Sleep is normal and a guard holds: check the helper by
        // re-asserting that (`disablesleep 0` when it is already 0).
        if probe, settings.enabled, helperUsable, !sleepDisabled {
            return effects + run(.apply(sleepDisabled: false, interactive: false), cause: cause,
                                 turningOn: turningOn, probe: true, now: now)
        }

        // Turned on while a guard holds: set the helper up now, while someone
        // is here to type the password, so it can start on its own later (on
        // the adapter, an app opening) without asking.
        if cause == .user, turningOn, settings.enabled, !helperUsable {
            return effects + run(.installHelper, cause: cause, turningOn: true, now: now)
        }
        return effects
    }
}

// MARK: - Settings page

/// What Settings → Lid shows: a view of the engine and nothing more.
public struct LidSettingsModel: Equatable, Sendable {

    /// The one-line state, top of the page and on the features page's card.
    public enum Status: Equatable, Sendable {
        /// The controller is not running (an inspection launch).
        case notManaged
        /// Switch off, normal sleep.
        case normal
        /// Keeping the Mac awake with the lid closed.
        case awake
        /// A change is in flight.
        case switching(Switching)
        /// On, but a guard lets the Mac sleep for now.
        case held(LidAwakeHold)
        /// On, the guards pass, and resuming needs the password.
        case needsYou
        /// SleepDisabled 1, set outside NotchHub.
        case outside
        /// NotchHub's SleepDisabled 1 that could not be put back.
        case stillOff
    }

    /// What the change in flight does.
    public enum Switching: Equatable, Sendable {
        case on
        case off
        case settingUp
        case removing
    }

    public var settings: LidAwakeSettings
    public var status: Status
    public var helperInstalled: Bool
    public var helperRefused: Bool
    public var note: LidAwakeNote?
    /// Which of the chosen apps are open.
    public var openApps: Set<String>
    public var busy: Bool

    public init(settings: LidAwakeSettings = LidAwakeSettings(), status: Status = .notManaged,
                helperInstalled: Bool = false, helperRefused: Bool = false, note: LidAwakeNote? = nil,
                openApps: Set<String> = [], busy: Bool = false) {
        self.settings = settings
        self.status = status
        self.helperInstalled = helperInstalled
        self.helperRefused = helperRefused
        self.note = note
        self.openApps = openApps
        self.busy = busy
    }

    /// The page for an engine's state.
    public init(engine: LidAwakeEngine, managed: Bool = true) {
        let status: Status
        if !managed {
            status = .notManaged
        } else if let flight = engine.inFlight, !flight.probe {
            switch flight.effect {
            case .apply(sleepDisabled: true, _): status = .switching(.on)
            case .installHelper: status = .switching(.settingUp)
            case .removeHelper: status = .switching(.removing)
            default: status = .switching(.off)
            }
        } else if engine.sleepDisabled && !engine.record.ownsSleepDisabled {
            status = .outside
        } else if engine.isKeepingAwake {
            // Kept only while the guards pass AND there is a silent way back.
            status = engine.verdict == .awake && engine.helperUsable ? .awake : .stillOff
        } else if engine.needsYou {
            status = .needsYou
        } else if case let .held(hold) = engine.verdict {
            status = .held(hold)
        } else {
            status = .normal
        }
        self.init(
            settings: engine.settings, status: status, helperInstalled: engine.helperInstalled,
            helperRefused: engine.helperRefused, note: engine.note,
            openApps: engine.running.intersection(engine.settings.apps), busy: engine.busy
        )
    }

    public var isAwake: Bool { status == .awake }

    /// The status line.
    public var headline: String {
        switch status {
        case .notManaged: return "Not managed in this launch"
        case .normal: return "Normal sleep"
        case .awake: return "Your Mac will keep working with the lid closed"
        case .switching(.on): return "Turning on…"
        case .switching(.off): return "Putting normal sleep back…"
        case .switching(.settingUp): return "Setting up…"
        case .switching(.removing): return "Removing the helper…"
        case let .held(hold): return Self.pausedLine(hold, settings: settings)
        case .needsYou: return "Paused: needs your password to resume"
        case .outside: return "Sleep is turned off outside NotchHub"
        case .stillOff: return "Sleep is still turned off"
        }
    }

    static func pausedLine(_ hold: LidAwakeHold, settings: LidAwakeSettings) -> String {
        switch hold {
        case .onBattery: return "Paused: on battery"
        case let .batteryLow(floor): return "Paused: battery at \(floor) % or below"
        case .noAppsChosen: return "Paused: no apps chosen"
        case .appsClosed: return "Paused: none of your apps is open"
        case .powerUnknown: return "Paused: can't read the battery"
        }
    }

    /// The line under the main switch: what closing the lid does now.
    public var detail: String {
        if let note {
            switch note {
            case let .timeUp(hours) where status == .normal || status == .stillOff:
                return "Turned itself off after \(hours) h. Closing the lid sleeps your Mac."
            case .cancelled where status == .normal || status == .stillOff || status == .needsYou:
                return "The password prompt was cancelled — nothing changed."
            case let .failed(why) where status != .awake:
                return "That didn't work: \(why)"
            default: break
            }
        }
        switch status {
        case .notManaged: return "NotchHub was opened for inspection; the switch is not live."
        case .normal: return "Closing the lid puts your Mac to sleep, as usual."
        case .awake: return "Closing the lid turns the screen off; apps keep running."
        case .switching: return "macOS may ask for your password."
        case .held(.onBattery): return "Closing the lid sleeps your Mac until it is on the power adapter."
        case .held(.batteryLow): return "Closing the lid sleeps your Mac until it charges."
        case .held(.noAppsChosen): return "Choose the apps to keep working for, below."
        case .held(.appsClosed): return "It keeps working again when one of them opens."
        case .held(.powerUnknown): return "Closing the lid sleeps your Mac until it can read the battery."
        case .needsYou:
            if !helperInstalled { return "The helper isn't set up, so resuming asks for your password." }
            if helperRefused { return "The helper isn't working, so your Mac sleeps as usual. Resume sets it up again." }
            return "The last change didn't take. Resume tries again."
        case .outside: return "Something other than NotchHub ran pmset disablesleep 1."
        case .stillOff: return "Closing the lid won't sleep your Mac until normal sleep is back."
        }
    }

    /// The features page's card: a few words.
    public var shortLabel: String {
        switch status {
        case .notManaged: return settings.enabled ? "On" : "Off"
        case .normal: return "Off — sleeps when closed"
        case .awake: return "On — keeps working when closed"
        case .switching: return "Switching…"
        case .held: return "On — paused"
        case .needsYou: return "On — paused, needs you"
        case .outside: return "Sleep off outside NotchHub"
        case .stillOff: return "Sleep still off"
        }
    }

    /// Lit on the card and the page: the switch is on.
    public var switchOn: Bool { settings.enabled }

    /// "Turns off at 18:40" when there is a clock.
    public func autoOffLine(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let deadline = settings.autoOffDeadline, deadline > now else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return "Turns off at \(formatter.string(from: deadline))"
    }

    /// The helper row's value.
    public var helperLabel: String {
        if !helperInstalled { return "Not set up" }
        return helperRefused ? "Not working" : "Set up ✓"
    }

    /// Whether a tap can do anything right now.
    public func isEnabled(_ intent: LidIntent) -> Bool {
        guard status != .notManaged, !busy else { return false }
        switch intent {
        case .batteryFloor:
            return !settings.onlyOnPower
        case .resume:
            return status == .needsYou
        case .restoreNormalSleep:
            return status == .outside || status == .stillOff
        case .removeHelper:
            return helperInstalled
        case .installHelper:
            return !helperInstalled || helperRefused
        default:
            return true
        }
    }
}

/// A tap in Settings → Lid. The view sends these and nothing else.
public enum LidIntent: Equatable, Sendable {
    case setEnabled(Bool)
    case onlyOnPower(Bool)
    case batteryFloor(Int)
    case onlyWhileApps(Bool)
    case addApp(bundleID: String)
    case removeApp(bundleID: String)
    /// Pick an app from /Applications (the app opens a panel).
    case chooseApp
    case autoOff(hours: Int?)
    case keepAfterQuit(Bool)
    case installHelper
    case removeHelper
    case resume
    case restoreNormalSleep
}
