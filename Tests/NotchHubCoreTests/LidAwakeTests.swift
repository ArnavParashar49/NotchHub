import Foundation
import Testing
@testable import NotchHubCore

private let t0 = Date(timeIntervalSince1970: 1_760_300_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
private let ac = PowerSnapshot(onAC: true, batteryPercent: 80)
private func battery(_ percent: Int) -> PowerSnapshot { PowerSnapshot(onAC: false, batteryPercent: percent) }

// MARK: - Settings

@Suite("Lid awake: settings")
struct LidAwakeSettingsTests {

    @Test("defaults: off, only on the adapter, a 20 % floor, no apps, no clock, sleep back on quit")
    func defaults() {
        let s = LidAwakeSettings()
        #expect(!s.enabled && s.onlyOnPower && s.batteryFloor == 20)
        #expect(!s.onlyWhileApps && s.apps.isEmpty && s.autoOffHours == nil && !s.keepAfterQuit)
        #expect(s.autoOffDeadline == nil)
    }

    @Test("the floor is 10–50 % in steps of 5; the clock only 1, 2, 4 or 8 hours")
    func clamping() {
        #expect(LidAwakeSettings.clampFloor(3) == 10)
        #expect(LidAwakeSettings.clampFloor(90) == 50)
        #expect(LidAwakeSettings.clampFloor(22) == 20)
        #expect(LidAwakeSettings.clampFloor(23) == 25)
        #expect(LidAwakeSettings(batteryFloor: 7).batteryFloor == 10)
        #expect(LidAwakeSettings(autoOffHours: 3).autoOffHours == nil)
        #expect(LidAwakeSettings.autoOffChoices.allSatisfy { LidAwakeSettings(autoOffHours: $0).autoOffHours == $0 })
    }

    @Test("apps are bundle identifiers: trimmed, each once, in the order added")
    func apps() {
        var s = LidAwakeSettings(apps: [" com.a.one ", "com.b.two", "com.a.one", ""])
        #expect(s.apps == ["com.a.one", "com.b.two"])
        s.addApp("com.c.three")
        s.addApp("com.b.two")
        #expect(s.apps == ["com.a.one", "com.b.two", "com.c.three"])
        s.removeApp("com.a.one")
        #expect(s.apps == ["com.b.two", "com.c.three"])
    }

    @Test("round-trips, and decodes an older or odd save with every missing key at its default")
    func codable() throws {
        let s = LidAwakeSettings(enabled: true, onlyOnPower: false, batteryFloor: 35, onlyWhileApps: true,
                                 apps: ["com.x"], autoOffHours: 4, keepAfterQuit: true, clockStart: t0)
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(LidAwakeSettings.self, from: data) == s)

        let old = try JSONDecoder().decode(LidAwakeSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        #expect(old == LidAwakeSettings(enabled: true))
        let odd = try JSONDecoder().decode(LidAwakeSettings.self, from: Data(#"{"batteryFloor":99,"autoOffHours":5,"apps":["a","a"],"future":1}"#.utf8))
        #expect(odd.batteryFloor == 50 && odd.autoOffHours == nil && odd.apps == ["a"])
    }

    @Test("settings and the record persist under their own keys")
    func persistence() {
        let suite = "NotchHubTests.lidAwake.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LidAwakeSettings.load(from: defaults) == LidAwakeSettings())
        #expect(LidAwakeRecord.load(from: defaults) == LidAwakeRecord())
        let s = LidAwakeSettings(enabled: true, apps: ["com.x"])
        s.save(to: defaults)
        LidAwakeRecord(ownsSleepDisabled: true, since: t0).save(to: defaults)
        #expect(LidAwakeSettings.load(from: defaults) == s)
        #expect(LidAwakeRecord.load(from: defaults) == LidAwakeRecord(ownsSleepDisabled: true, since: t0))
        #expect(LidAwakeSettings.defaultsKey != LidAwakeRecord.defaultsKey)
    }

    @Test("the deadline is the clock's start plus the hours, only while on")
    func deadline() {
        var s = LidAwakeSettings(enabled: true, autoOffHours: 2, clockStart: t0)
        #expect(s.autoOffDeadline == at(7200))
        s.enabled = false
        #expect(s.autoOffDeadline == nil)
    }
}

// MARK: - Policy

@Suite("Lid awake: the guards")
struct LidAwakePolicyTests {

    func verdict(_ s: LidAwakeSettings, _ power: PowerSnapshot?, running: Set<String> = [], now: Date = t0,
                 latched: Bool = false) -> LidAwakeVerdict {
        LidAwakePolicy.verdict(settings: s, power: power, running: running, now: now, lowLatched: latched).verdict
    }

    @Test("off is off, whatever else is true")
    func off() {
        #expect(verdict(LidAwakeSettings(), ac) == .off)
    }

    @Test("only on the adapter: awake on AC, held on battery — and an unknown power source counts as battery")
    func onlyOnPower() {
        let s = LidAwakeSettings(enabled: true)
        #expect(verdict(s, ac) == .awake)
        #expect(verdict(s, battery(95)) == .held(.onBattery))
        #expect(verdict(s, nil) == .held(.onBattery))
    }

    @Test("the battery floor (adapter guard off): held at or below it, with a 3 % margin before it re-arms")
    func floor() {
        let s = LidAwakeSettings(enabled: true, onlyOnPower: false, batteryFloor: 20)
        #expect(verdict(s, battery(21)) == .awake)
        let low = LidAwakePolicy.verdict(settings: s, power: battery(20), running: [], now: t0, lowLatched: false)
        #expect(low.verdict == .held(.batteryLow(floor: 20)) && low.lowLatched)
        // Latched: a reading wobbling back up does not flap it.
        #expect(verdict(s, battery(22), latched: true) == .held(.batteryLow(floor: 20)))
        #expect(verdict(s, battery(23), latched: true) == .awake)
        // On the adapter the floor never applies.
        #expect(verdict(s, PowerSnapshot(onAC: true, batteryPercent: 5), latched: true) == .awake)
        // On battery with no charge to compare: held, whatever the latch.
        #expect(verdict(s, PowerSnapshot(onAC: false, batteryPercent: nil), latched: true) == .held(.powerUnknown))
        #expect(verdict(s, PowerSnapshot(onAC: false, batteryPercent: nil), latched: false) == .held(.powerUnknown))
        // …and the latch is kept as it was for the next real reading.
        let unknown = LidAwakePolicy.verdict(settings: s, power: PowerSnapshot(onAC: false, batteryPercent: nil),
                                             running: [], now: t0, lowLatched: true)
        #expect(unknown.lowLatched)
        // A raised floor.
        #expect(verdict(LidAwakeSettings(enabled: true, onlyOnPower: false, batteryFloor: 50), battery(45)) == .held(.batteryLow(floor: 50)))
    }

    @Test("the battery floor with the power source unreadable: held, never awake on a guess")
    func floorUnknownPower() {
        let s = LidAwakeSettings(enabled: true, onlyOnPower: false)
        #expect(verdict(s, nil) == .held(.powerUnknown))
        #expect(verdict(s, nil, latched: true) == .held(.powerUnknown))
        #expect(LidSettingsModel(settings: s, status: .held(.powerUnknown)).headline == "Paused: can't read the battery")
    }

    @Test("only while these apps are open: none chosen holds, none running holds, any one running keeps it awake")
    func apps() {
        var s = LidAwakeSettings(enabled: true, onlyWhileApps: true)
        #expect(verdict(s, ac) == .held(.noAppsChosen))
        s.apps = ["com.example.agent", "com.example.chat"]
        #expect(verdict(s, ac, running: ["com.apple.finder"]) == .held(.appsClosed))
        #expect(verdict(s, ac, running: ["com.apple.finder", "com.example.chat"]) == .awake)
        // The power guard comes first.
        #expect(verdict(s, battery(90), running: ["com.example.chat"]) == .held(.onBattery))
    }

    @Test("the auto-off clock: awake until the deadline, then expired")
    func clock() {
        let s = LidAwakeSettings(enabled: true, autoOffHours: 1, clockStart: t0)
        #expect(verdict(s, ac, now: at(3599)) == .awake)
        #expect(verdict(s, ac, now: at(3600)) == .expired)
        #expect(verdict(s, battery(50), now: at(3600)) == .expired)
    }
}

// MARK: - Commands, the helper rule, AppleScript

@Suite("Lid awake: commands")
struct LidAwakeCommandTests {

    @Test("only pmset -a disablesleep 0 / 1, and sudo -n never prompts")
    func commands() {
        #expect(LidAwakeCommands.pmsetArguments(sleepDisabled: true) == ["-a", "disablesleep", "1"])
        #expect(LidAwakeCommands.pmsetArguments(sleepDisabled: false) == ["-a", "disablesleep", "0"])
        #expect(LidAwakeCommands.pmsetLine(sleepDisabled: true) == "/usr/bin/pmset -a disablesleep 1")
        #expect(LidAwakeCommands.sudoArguments(sleepDisabled: false) == ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"])
        #expect(LidAwakeCommands.readArguments == ["-g"])
        #expect(LidAwakeCommands.sleepNowArguments == ["sleepnow"])
    }

    static let pmsetNormal = """
    System-wide power settings:
    Currently in use:
     standby              1
     Sleep On Power Button 1
     hibernatefile        /var/vm/sleepimage
     powernap             1
     sleep                1 (sleep prevented by powerd, coreaudiod)
     displaysleep         10
    """

    @Test("pmset -g: SleepDisabled 1 / 0, absent means normal sleep, and anything else is unknown")
    func parse() {
        let disabled = "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n standby              1\n"
        #expect(LidAwakeCommands.sleepDisabled(inPmsetOutput: disabled) == true)
        #expect(LidAwakeCommands.sleepDisabled(inPmsetOutput: disabled.replacingOccurrences(of: "\t\t1", with: "  0")) == false)
        #expect(LidAwakeCommands.sleepDisabled(inPmsetOutput: Self.pmsetNormal) == false)
        #expect(LidAwakeCommands.sleepDisabled(inPmsetOutput: "") == nil)
        #expect(LidAwakeCommands.sleepDisabled(inPmsetOutput: "pmset: command failed") == nil)
        #expect(LidAwakeCommands.sleepDisabled(inPmsetOutput: " SleepDisabled  maybe\nCurrently in use:\n") == nil)
        // A different key that merely contains the name is not it.
        #expect(LidAwakeCommands.sleepDisabled(inPmsetOutput: "Currently in use:\n NotSleepDisabled 1\n") == false)
    }

    @Test("the helper rule, exactly, for a valid short name")
    func rule() throws {
        let rule = try #require(LidAwakeHelperRule(user: "arnav"))
        #expect(rule.content == "arnav ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n")
        #expect(LidAwakeHelperRule.path == "/private/etc/sudoers.d/notchhub-lid")
        // sudo skips a name with a dot in it: the real file must have none.
        #expect(!LidAwakeHelperRule.fileName.contains("."))
        #expect(LidAwakeHelperRule(user: "j.doe-2")?.line.hasPrefix("j.doe-2 ALL=(root) NOPASSWD: ") == true)
        #expect(LidAwakeHelperRule(user: "_svc") != nil)
        // Capitals are fine in a name that isn't all capitals.
        #expect(LidAwakeHelperRule(user: "Arnav") != nil && LidAwakeHelperRule(user: "Jo_B2") != nil)
    }

    @Test("names sudoers would not read as this user are refused: ALL (everyone) and all-capital aliases")
    func aliasNames() {
        for name in ["ALL", "ADMIN", "WHEEL_2", "A", "X1"] {
            #expect(LidAwakeHelperRule(user: name) == nil, "\(name) must be refused")
        }
    }

    @Test("a name that would need sudoers escaping is refused, never escaped")
    func badNames() {
        for name in ["", "a b", "x;rm", "o'neil", "a\"b", "a\nb", "name#", "a,b", "a:b", "a=b", "-x", ".x", "%admin", "a\\b", "ünïcode",
                     String(repeating: "a", count: 65)] {
            #expect(LidAwakeHelperRule(user: name) == nil, "\(name.debugDescription) must be refused")
        }
    }

    @Test("install: a dot-named temp beside the target, visudo -cf before it moves, root:wheel 0440, the whole policy re-checked — and no pmset")
    func installScript() throws {
        let rule = try #require(LidAwakeHelperRule(user: "arnav"))
        let script = rule.installScript()
        let steps = script.components(separatedBy: "; ")
        func index(_ prefix: String) -> Int { steps.firstIndex { $0.hasPrefix(prefix) } ?? -1 }
        #expect(steps.first == "set -e")
        #expect(steps.contains("t=$(/usr/bin/mktemp /private/etc/sudoers.d/.notchhub-lid.XXXXXX)"))
        #expect(steps.contains(#"/usr/bin/printf '%s\n' 'arnav ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1' > "$t""#))
        let check = index("/usr/sbin/visudo -cf"), chown = index("/usr/sbin/chown root:wheel"),
            chmod = index("/bin/chmod 0440"), move = index("/bin/mv -f \"$t\" /private/etc/sudoers.d/notchhub-lid"),
            whole = index("/usr/sbin/visudo -c >/dev/null")
        #expect(check > 0 && check < chown && chown < chmod && chmod < move && move < whole)
        #expect(!script.contains("\n"))
        // Sleep is never turned off through the dialog: only through the rule, once it is in place.
        #expect(!script.contains("; /usr/bin/pmset")
                && script.hasSuffix("; /usr/sbin/visudo -c >/dev/null || { /bin/rm -f /private/etc/sudoers.d/notchhub-lid; exit 1; }"))
    }

    @Test("the install script is valid sh")
    func installScriptParses() async throws {
        let rule = try #require(LidAwakeHelperRule(user: "arnav"))
        for script in [rule.installScript(), LidAwakeHelperRule.uninstallScript(thenSleepDisabled: false),
                       LidAwakeCommands.watchdogScript(pid: 123, uid: 501, processName: "NotchHub")] {
            // -n: parse only, run nothing.
            #expect(try await runTool("/bin/sh", ["-n", "-c", script]).status == 0)
        }
    }

    @Test("the dead-man's switch: waits for the pid, steps aside for a relaunched NotchHub, then the helper's disablesleep 0")
    func watchdogScript() {
        let script = LidAwakeCommands.watchdogScript(pid: 4242, uid: 501, processName: "NotchHub")
        #expect(script == ": notchhub-lid-watchdog; trap '' HUP INT; "
                + "while /bin/kill -0 4242 2>/dev/null; do /bin/sleep 5; done; "
                + "/usr/bin/pgrep -q -x -U 501 NotchHub && exit 0; "
                + "exec /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0")
        #expect(LidAwakeCommands.helperRestoreLine == "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0")
        // A name that isn't plain never goes into the script.
        let odd = LidAwakeCommands.watchdogScript(pid: 1, uid: 501, processName: "a b;rm", interval: 0.5)
        #expect(!odd.contains("pgrep") && !odd.contains("rm") && odd.contains("/bin/sleep 0.5;"))
    }

    @Test("the dead-man's switch, run for real with a harmless command: fires when the pid is gone, steps aside if a same-named process runs")
    func watchdogRuns() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lid-watchdog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func watched(_ seconds: String) throws -> Process {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sleep")
            p.arguments = [seconds]
            try p.run()
            return p
        }
        // Fires: the watched process ends, no process by that name is running.
        let fired = dir.appendingPathComponent("fired")
        let a = try watched("0.3")
        let script = LidAwakeCommands.watchdogScript(pid: a.processIdentifier, uid: getuid(), processName: "nh-no-such-process",
                                                     interval: 0.1, restore: "/usr/bin/touch '\(fired.path)'")
        #expect(try await runTool("/bin/sh", ["-c", script]).status == 0)
        #expect(FileManager.default.fileExists(atPath: fired.path))

        // Steps aside: another process by the name is running (a relaunch).
        let aside = dir.appendingPathComponent("aside")
        let other = try watched("5")
        defer { other.terminate() }
        let b = try watched("0.3")
        let script2 = LidAwakeCommands.watchdogScript(pid: b.processIdentifier, uid: getuid(), processName: "sleep",
                                                      interval: 0.1, restore: "/usr/bin/touch '\(aside.path)'")
        #expect(try await runTool("/bin/sh", ["-c", script2]).status == 0)
        #expect(!FileManager.default.fileExists(atPath: aside.path))
    }

    @Test("uninstall: normal sleep back first (when asked), then the rule goes")
    func uninstall() {
        #expect(LidAwakeHelperRule.uninstallScript() == "/bin/rm -f /private/etc/sudoers.d/notchhub-lid")
        #expect(LidAwakeHelperRule.uninstallScript(thenSleepDisabled: false)
                == "/usr/bin/pmset -a disablesleep 0; /bin/rm -f /private/etc/sudoers.d/notchhub-lid")
    }

    @Test("AppleScript: backslashes, then quotes, escaped; the prompt too")
    func appleScript() throws {
        #expect(AppleScriptSource.quoted(#"plain"#) == #""plain""#)
        #expect(AppleScriptSource.quoted(#"say "hi""#) == #""say \"hi\"""#)
        #expect(AppleScriptSource.quoted(#"a\nb"#) == #""a\\nb""#)
        #expect(AppleScriptSource.quoted(#"\""#) == #""\\\"""#)
        #expect(AppleScriptSource.adminShellScript("/usr/bin/pmset -a disablesleep 0", prompt: #"NotchHub "lid""#)
                == #"do shell script "/usr/bin/pmset -a disablesleep 0" with prompt "NotchHub \"lid\"" with administrator privileges"#)
        // The real install script survives the trip: its quotes and its \n.
        let rule = try #require(LidAwakeHelperRule(user: "arnav"))
        let source = AppleScriptSource.adminShellScript(rule.installScript(), prompt: "p")
        #expect(source.contains(#"/usr/bin/printf '%s\\n'"#))
        #expect(source.contains(#"> \"$t\""#))
        #expect(AppleScriptSource.isUserCancel("0:150: execution error: User canceled. (-128)"))
        #expect(!AppleScriptSource.isUserCancel("0:150: execution error: sh: bad (1)"))
    }

    @Test("the admin script compiles (osacompile: compiled, never run)")
    func appleScriptCompiles() async throws {
        let rule = try #require(LidAwakeHelperRule(user: "arnav"))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("lid-\(UUID().uuidString).scpt")
        defer { try? FileManager.default.removeItem(at: out) }
        for script in [rule.installScript(), LidAwakeCommands.pmsetLine(sleepDisabled: false)] {
            let source = AppleScriptSource.adminShellScript(script, prompt: #"NotchHub wants to keep your Mac "awake""#)
            #expect(try await runTool("/usr/bin/osacompile", ["-o", out.path, "-e", source]).status == 0)
        }
    }

    @Test("an escaped string comes back out of AppleScript exactly as it went in")
    func appleScriptRoundTrip() async throws {
        let rule = try #require(LidAwakeHelperRule(user: "arnav"))
        for text in [rule.installScript(), #"a "quoted" \ back\slash \n"#] {
            // `return` a literal: no shell, no privileges — just the string.
            let result = try await runTool("/usr/bin/osascript", ["-e", "return \(AppleScriptSource.quoted(text))"])
            #expect(result.status == 0)
            #expect(result.output == text + "\n")
        }
    }
}

/// Runs a tool and returns its exit status and standard output — without
/// blocking a Swift-concurrency thread: the exit comes back through
/// `terminationHandler` (never `waitUntilExit`, which spins whichever
/// thread's run loop it is called on), and the output is read on a global
/// queue. Other suites' tests share the cooperative pool.
func runTool(_ tool: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    return try await withCheckedThrowingContinuation { continuation in
        let output = ToolOutput()
        let group = DispatchGroup()
        group.enter()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
            return
        }
        DispatchQueue.global().async {
            output.data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.notify(queue: .global()) {
            continuation.resume(returning: (process.terminationStatus, String(decoding: output.data, as: UTF8.self)))
        }
    }
}

private final class ToolOutput: @unchecked Sendable {
    var data = Data()
}

// MARK: - The state machine

/// An engine in a box, for `#expect`.
private final class Machine {
    var engine: LidAwakeEngine
    init(_ settings: LidAwakeSettings = LidAwakeSettings(), record: LidAwakeRecord = LidAwakeRecord(), helper: Bool = true) {
        engine = LidAwakeEngine(settings: settings, record: record, helperInstalled: helper)
    }
    /// Launches; a check of the helper that launch starts (a probe) is
    /// finished as `probeWorks` says, or left in flight when `nil`.
    @discardableResult
    func launch(observed: Bool?, power: PowerSnapshot? = ac, running: Set<String> = [], helper: Bool? = nil, now: Date = t0,
                probeWorks: Bool? = true) -> [LidAwakeEffect] {
        let effects = engine.launch(observed: observed, power: power, running: running,
                                    helperInstalled: helper ?? engine.helperInstalled, now: now)
        if let probeWorks, engine.inFlight?.probe == true {
            finish(probeWorks ? .done : .failed("sudo: a password is required"), worked: probeWorks, now: now)
        }
        return effects
    }
    /// Finishes the command in flight as it would on a real Mac: the read
    /// afterwards shows what the command set when it worked.
    @discardableResult
    func finish(_ outcome: LidAwakeOutcome = .done, observed: Bool?? = .none, helper: Bool? = nil, worked: Bool? = nil,
                askedAdmin: Bool = false, now: Date = t0) -> [LidAwakeEffect] {
        let target = engine.inFlight?.effect.target
        let read: Bool?
        switch observed {
        case let .some(value): read = value
        // Failed: the system is as the last read left it.
        case .none: read = outcome == .done ? (target ?? engine.observed) : engine.observed
        }
        var installed = helper ?? engine.helperInstalled
        if helper == nil, outcome == .done, let effect = engine.inFlight?.effect {
            if case .installHelper = effect { installed = true }
            if case .removeHelper = effect { installed = false }
        }
        return engine.finished(outcome: outcome, observed: read, helperInstalled: installed, helperWorked: worked,
                               askedAdmin: askedAdmin, now: now)
    }
    var status: LidSettingsModel.Status { LidSettingsModel(engine: engine).status }
    var model: LidSettingsModel { LidSettingsModel(engine: engine) }
}

@Suite("Lid awake: the state machine")
struct LidAwakeEngineTests {

    // MARK: Crash reconcile

    @Test("launch: NotchHub's SleepDisabled 1 with the switch off is put back (the dialog may show — safety first)")
    func reconcileRestores() {
        let m = Machine(record: LidAwakeRecord(ownsSleepDisabled: true, since: at(-600)))
        #expect(m.launch(observed: true) == [.apply(sleepDisabled: false, interactive: true)])
        #expect(m.status == .switching(.off))
        let after = m.finish()
        #expect(after == [.saveRecord, .nudgeSleep])
        #expect(m.engine.record == LidAwakeRecord() && m.status == .normal)
    }

    @Test("launch: a guard holding (on battery) puts NotchHub's SleepDisabled back too")
    func reconcileGuard() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        #expect(m.launch(observed: true, power: battery(70)) == [.apply(sleepDisabled: false, interactive: true)])
    }

    @Test("launch: a SleepDisabled 1 NotchHub did not set is left alone, and shown")
    func reconcileOutside() {
        let m = Machine()
        #expect(m.launch(observed: true).isEmpty)
        #expect(m.status == .outside)
        #expect(m.model.isEnabled(.restoreNormalSleep))
        #expect(m.engine.restoreNormalSleep(now: t0) == [.apply(sleepDisabled: false, interactive: true)])
        m.finish()
        #expect(m.status == .normal && !m.engine.sleepDisabled)
    }

    @Test("launch: a record whose SleepDisabled is 0 is stale — cleared, nothing run")
    func reconcileStale() {
        let m = Machine(record: LidAwakeRecord(ownsSleepDisabled: true, since: t0))
        #expect(m.launch(observed: false) == [.saveRecord])
        #expect(m.engine.record == LidAwakeRecord())
    }

    @Test("launch: on, guards passing, already off — kept, and the helper checked by re-asserting the 1 it set (not shown as a change)")
    func reconcileKeeps() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        #expect(m.launch(observed: true, probeWorks: nil) == [.apply(sleepDisabled: true, interactive: false)])
        #expect(m.engine.inFlight?.probe == true && m.status == .awake)
        #expect(m.finish(worked: true).isEmpty)
        #expect(m.status == .awake && m.engine.probedAt == t0)
    }

    @Test("launch: kept awake but the helper no longer works — normal sleep goes back (one dialog), and it waits for Resume")
    func reconcileBrokenHelper() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        _ = m.launch(observed: true, probeWorks: nil)
        let after = m.finish(.failed("sudo: a password is required"), worked: false)
        #expect(after == [.apply(sleepDisabled: false, interactive: true)])
        #expect(m.engine.helperRefused && m.engine.needsYou && m.status == .switching(.off))
        // The probe's own failure is the helper row's news, not a note.
        #expect(m.engine.note == nil)
        m.finish(worked: false, askedAdmin: true)
        #expect(!m.engine.sleepDisabled && m.engine.record == LidAwakeRecord())
        #expect(m.status == .needsYou && m.model.detail.contains("helper isn't working"))
    }

    @Test("launch: on and guards passing turns it on with the helper — the record written FIRST — and never prompts without one")
    func reconcileEnables() {
        let m = Machine(LidAwakeSettings(enabled: true))
        #expect(m.launch(observed: false) == [.saveRecord, .apply(sleepDisabled: true, interactive: false)])
        #expect(m.engine.record.ownsSleepDisabled)
        m.finish()
        #expect(m.status == .awake)

        let noHelper = Machine(LidAwakeSettings(enabled: true), helper: false)
        #expect(noHelper.launch(observed: false).isEmpty)
        #expect(noHelper.status == .needsYou && !noHelper.engine.record.ownsSleepDisabled)
    }

    @Test("launch: on, a guard holding, sleep normal — the helper is checked with the harmless disablesleep 0")
    func reconcileProbeHeld() {
        let m = Machine(LidAwakeSettings(enabled: true))
        #expect(m.launch(observed: false, power: battery(80), probeWorks: nil) == [.apply(sleepDisabled: false, interactive: false)])
        #expect(m.status == .held(.onBattery))
        // Fine: no nudge, no note — nothing happened.
        #expect(m.finish(worked: true).isEmpty)
        // Refused: the helper row says so; the page stays paused, no prompt.
        let bad = Machine(LidAwakeSettings(enabled: true))
        _ = bad.launch(observed: false, power: battery(80), probeWorks: false)
        #expect(bad.engine.helperRefused && bad.model.helperLabel == "Not working" && bad.status == .held(.onBattery))
        #expect(bad.engine.note == nil)
    }

    @Test("an unreadable pmset falls back on the record")
    func reconcileUnknown() {
        let m = Machine(record: LidAwakeRecord(ownsSleepDisabled: true))
        #expect(m.launch(observed: nil) == [.apply(sleepDisabled: false, interactive: true)])
    }

    @Test("before launch (an inspection run) nothing is ever run")
    func notStarted() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        #expect(m.engine.update(power: battery(10), now: t0).isEmpty)
        #expect(m.engine.setEnabled(false, now: t0) == [.saveSettings])
        #expect(LidSettingsModel(engine: m.engine, managed: false).status == .notManaged)
        #expect(!LidSettingsModel(engine: m.engine, managed: false).isEnabled(.setEnabled(true)))
    }

    // MARK: The switch

    @Test("turning it on the first time: one dialog installs the helper, then sleep goes off THROUGH it — the record first")
    func firstEnable() {
        let m = Machine(helper: false)
        m.launch(observed: false)
        #expect(m.engine.setEnabled(true, now: t0) == [.saveSettings, .installHelper])
        #expect(m.status == .switching(.settingUp) && !m.engine.record.ownsSleepDisabled)
        #expect(m.finish() == [.saveRecord, .apply(sleepDisabled: true, interactive: false)])
        #expect(m.status == .switching(.on) && m.engine.record.ownsSleepDisabled)
        m.finish(worked: true)
        #expect(m.status == .awake && m.engine.helperUsable && m.engine.record.ownsSleepDisabled)
    }

    @Test("the helper installed but refused by sudo: sleep is never turned off, the switch goes back off, the row says so")
    func firstEnableRefused() {
        let m = Machine(helper: false)
        m.launch(observed: false)
        _ = m.engine.setEnabled(true, now: t0)
        m.finish()
        let after = m.finish(.failed("sudo: a password is required"), worked: false)
        #expect(after.contains(.saveSettings) && after.contains(.saveRecord))
        // Nothing falls back on the dialog to turn sleep off.
        #expect(!after.contains { $0.runsCommand })
        #expect(!m.engine.settings.enabled && !m.engine.sleepDisabled && !m.engine.record.ownsSleepDisabled)
        #expect(m.status == .normal && m.model.helperLabel == "Not working" && m.model.isEnabled(.installHelper))
        #expect(m.model.detail == "That didn't work: sudo: a password is required")
    }

    @Test("cancelling the password prompt turns the switch back off; nothing was recorded")
    func enableCancelled() {
        let m = Machine(helper: false)
        m.launch(observed: false)
        _ = m.engine.setEnabled(true, now: t0)
        #expect(m.finish(.cancelled) == [.saveSettings])
        #expect(!m.engine.settings.enabled && !m.engine.record.ownsSleepDisabled)
        #expect(m.status == .normal && m.model.detail.contains("cancelled"))
    }

    @Test("with the helper, turning it on goes through the helper only; turning it off may fall back on the dialog")
    func enableWithHelper() {
        let m = Machine()
        m.launch(observed: false)
        #expect(m.engine.setEnabled(true, now: t0) == [.saveSettings, .saveRecord, .apply(sleepDisabled: true, interactive: false)])
        m.finish(worked: true)
        #expect(m.status == .awake)
        #expect(m.engine.setEnabled(false, now: t0) == [.saveSettings, .apply(sleepDisabled: false, interactive: true)])
        // The person turned it off: no sleep nudge.
        #expect(m.finish(worked: true) == [.saveRecord])
        #expect(m.status == .normal)
    }

    @Test("turned on while a guard holds: the helper is set up now (one prompt) and checked; it starts on its own later")
    func enableWhileHeld() {
        let m = Machine(helper: false)
        m.launch(observed: false, power: battery(80))
        #expect(m.engine.setEnabled(true, now: t0) == [.saveSettings, .installHelper])
        #expect(m.status == .switching(.settingUp))
        // Installed: checked at once with the harmless disablesleep 0.
        #expect(m.finish() == [.apply(sleepDisabled: false, interactive: false)])
        #expect(m.finish(worked: true).isEmpty)
        #expect(m.status == .held(.onBattery) && !m.engine.record.ownsSleepDisabled)
        // Plugged in: on with the helper, no prompt.
        #expect(m.engine.update(power: ac, now: at(60)) == [.saveRecord, .apply(sleepDisabled: true, interactive: false)])
    }

    @Test("set-up cancelled while held: the switch goes back off")
    func setupCancelled() {
        let m = Machine(helper: false)
        m.launch(observed: false, power: battery(80))
        _ = m.engine.setEnabled(true, now: t0)
        m.finish(.cancelled)
        #expect(!m.engine.settings.enabled)
    }

    @Test("Set Up… with the switch off installs and checks the rule, so the row is true at once")
    func setUpAlone() {
        let m = Machine(LidAwakeSettings(), helper: false)
        m.launch(observed: false)
        #expect(m.engine.installHelper(now: t0) == [.installHelper])
        // Off: no check to make by use; the row reads what the file says.
        #expect(m.finish().isEmpty)
        #expect(m.model.helperLabel == "Set up ✓")
    }

    // MARK: Guards acting on their own

    @Test("unplugged while awake: normal sleep back, then a nudge so a closed Mac really sleeps; plugged back in: on again")
    func unplugReplug() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true)
        #expect(m.engine.update(power: battery(90), now: at(10)) == [.apply(sleepDisabled: false, interactive: true)])
        #expect(m.finish(worked: true) == [.saveRecord, .nudgeSleep])
        #expect(m.status == .held(.onBattery) && m.model.headline == "Paused: on battery")
        #expect(m.engine.update(power: ac, now: at(20)) == [.saveRecord, .apply(sleepDisabled: true, interactive: false)])
        m.finish(worked: true)
        #expect(m.status == .awake)
    }

    @Test("the battery floor lets the Mac sleep at 20 %, and not again until 23 % or the adapter")
    func floorPath() {
        let m = Machine(LidAwakeSettings(enabled: true, onlyOnPower: false), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true, power: battery(30))
        #expect(m.engine.update(power: battery(21), now: t0).isEmpty)
        #expect(m.engine.update(power: battery(20), now: t0) == [.apply(sleepDisabled: false, interactive: true)])
        m.finish()
        #expect(m.status == .held(.batteryLow(floor: 20)) && m.model.headline == "Paused: battery at 20 % or below")
        #expect(m.engine.update(power: battery(22), now: t0).isEmpty)
        #expect(m.engine.update(power: PowerSnapshot(onAC: true, batteryPercent: 22), now: t0).contains(.apply(sleepDisabled: true, interactive: false)))
    }

    @Test("the chosen apps: the last one quitting puts sleep back; one opening turns it off again")
    func appsPath() {
        let s = LidAwakeSettings(enabled: true, onlyWhileApps: true, apps: ["com.example.agent"])
        let m = Machine(s, record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true, running: ["com.example.agent", "com.apple.finder"])
        #expect(m.status == .awake && m.model.openApps == ["com.example.agent"])
        #expect(m.engine.update(running: ["com.apple.finder"], now: t0) == [.apply(sleepDisabled: false, interactive: true)])
        m.finish()
        #expect(m.status == .held(.appsClosed))
        #expect(m.engine.update(running: ["com.example.agent"], now: t0) == [.saveRecord, .apply(sleepDisabled: true, interactive: false)])
    }

    @Test("auto-off: at the deadline the switch turns itself off and sleep goes back; it says so")
    func autoOff() {
        let m = Machine(LidAwakeSettings(enabled: true, autoOffHours: 2, clockStart: t0), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true, now: at(60))
        #expect(m.engine.tick(now: at(7199)).isEmpty)
        #expect(m.engine.tick(now: at(7200)) == [.saveSettings, .apply(sleepDisabled: false, interactive: true)])
        #expect(!m.engine.settings.enabled)
        #expect(m.finish(now: at(7201)) == [.saveRecord, .nudgeSleep])
        #expect(m.status == .normal && m.model.detail == "Turned itself off after 2 h. Closing the lid sleeps your Mac.")
        // Turning it on again clears the note and starts a new clock.
        _ = m.engine.setEnabled(true, now: at(8000))
        #expect(m.engine.note == nil && m.engine.settings.clockStart == at(8000))
    }

    @Test("choosing a clock while on starts it now, not from when the switch went on")
    func clockRestart() {
        let m = Machine(LidAwakeSettings(enabled: true, clockStart: t0), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true)
        #expect(m.engine.change(now: at(5 * 3600)) { $0.autoOffHours = 4 } == [.saveSettings])
        #expect(m.engine.settings.autoOffDeadline == at(9 * 3600))
        #expect(m.model.autoOffLine(now: at(5 * 3600), calendar: Self.utc, locale: Locale(identifier: "en_GB")) == "Turns off at \(Self.hhmm(at(9 * 3600)))")
        #expect(m.engine.change(now: at(6 * 3600)) { $0.autoOffHours = nil } == [.saveSettings])
        #expect(m.engine.settings.autoOffDeadline == nil && m.engine.settings.clockStart == at(6 * 3600))
    }

    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    static func hhmm(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    @Test("one command at a time: changes while one runs are looked at when it finishes")
    func oneAtATime() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true)
        #expect(m.engine.update(power: battery(90), now: t0) == [.apply(sleepDisabled: false, interactive: true)])
        // Plugged back in mid-flight: nothing new yet.
        #expect(m.engine.update(power: ac, now: t0).isEmpty)
        // When the restore finishes, the Mac is on the adapter again: back on.
        let after = m.finish()
        #expect(after == [.saveRecord, .nudgeSleep, .saveRecord, .apply(sleepDisabled: true, interactive: false)])
    }

    @Test("the helper refused (sudo -n): paused, never retried on its own, and Resume reinstalls it in one prompt")
    func helperRefused() {
        let m = Machine(LidAwakeSettings(enabled: true))
        m.launch(observed: false, power: battery(80))
        #expect(m.engine.update(power: ac, now: t0) == [.saveRecord, .apply(sleepDisabled: true, interactive: false)])
        m.finish(.failed("a password is required"), observed: false, worked: false)
        #expect(m.status == .needsYou && m.engine.helperRefused && m.model.helperLabel == "Not working")
        #expect(!m.engine.record.ownsSleepDisabled)
        // No prompt loop on further events.
        #expect(m.engine.update(power: PowerSnapshot(onAC: true, batteryPercent: 81), now: t0).isEmpty)
        #expect(m.model.isEnabled(.resume) && m.model.isEnabled(.installHelper))
        #expect(m.engine.resume(now: t0) == [.installHelper])
        #expect(m.finish() == [.saveRecord, .apply(sleepDisabled: true, interactive: false)])
        m.finish(worked: true)
        #expect(m.status == .awake && !m.engine.helperRefused)
    }

    @Test("an automatic restore that fails is retried — silently — on every later fact and tick; never latched off")
    func restoreRetried() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true)
        #expect(m.engine.update(power: battery(79), now: t0) == [.apply(sleepDisabled: false, interactive: true)])
        // The helper failed and the dialog, shown, timed out behind a closed lid.
        let after = m.finish(.failed("the password prompt timed out"), worked: false, askedAdmin: true)
        // No straight-back loop…
        #expect(after.isEmpty && m.engine.restorePending && m.engine.restorePromptShown)
        #expect(m.status == .stillOff)
        // …but every later fact tries the helper again, without the dialog.
        #expect(m.engine.update(power: battery(70), now: t0) == [.apply(sleepDisabled: false, interactive: false)])
        #expect(m.finish(.failed("sudo: a password is required"), worked: false).isEmpty)
        #expect(m.engine.tick(now: at(60)) == [.apply(sleepDisabled: false, interactive: false)])
        #expect(m.finish(.failed("sudo: a password is required"), worked: false).isEmpty)
        #expect(m.engine.update(observed: true, helperInstalled: true, now: at(120)) == [.apply(sleepDisabled: false, interactive: false)])
        // The helper works again: normal sleep is back, the hold is over.
        #expect(m.finish(worked: true) == [.saveRecord, .nudgeSleep])
        #expect(!m.engine.restorePending && !m.engine.restorePromptShown && m.status == .held(.onBattery))
    }

    @Test("the dialog for an automatic restore is offered once per hold — until it is actually shown (a closed lid isn't asked)")
    func restorePromptOncePerHold() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true)
        _ = m.engine.update(power: battery(79), now: t0)
        // The controller didn't show it (the lid was closed): still allowed next time.
        m.finish(.failed("sudo: a password is required"), worked: false, askedAdmin: false)
        #expect(m.engine.tick(now: at(60)) == [.apply(sleepDisabled: false, interactive: true)])
        // Shown and cancelled: from now on the helper only.
        m.finish(.cancelled, worked: false, askedAdmin: true)
        #expect(m.engine.tick(now: at(120)) == [.apply(sleepDisabled: false, interactive: false)])
        m.finish(.failed("sudo: a password is required"), worked: false)
        // Someone at the page asks again.
        #expect(m.engine.change(now: at(130)) { $0.batteryFloor = 30 } == [.saveSettings, .apply(sleepDisabled: false, interactive: true)])
    }

    @Test("a sub-setting never prompts to keep the Mac awake: no helper → Resume, not a password dialog")
    func settingsNeverPromptToWake() {
        let m = Machine(LidAwakeSettings(enabled: true, onlyWhileApps: true, apps: ["com.example.agent"]), helper: false)
        m.launch(observed: false, running: ["com.example.agent"])
        #expect(m.engine.needsYou)
        #expect(m.engine.change(now: t0) { $0.keepAfterQuit = true } == [.saveSettings])
        #expect(m.engine.change(now: t0) { $0.addApp("com.example.chat") } == [.saveSettings])
        #expect(m.status == .needsYou)
        // A refused helper: the same.
        let r = Machine(LidAwakeSettings(enabled: true))
        r.launch(observed: false, power: battery(80), probeWorks: false)
        #expect(r.engine.change(now: t0) { $0.onlyOnPower = false } == [.saveSettings])
        #expect(r.status == .needsYou)
    }

    @Test("a command that “worked” but left pmset unchanged is a failure, and is not retried in a loop")
    func didNotTake() {
        let m = Machine(LidAwakeSettings(enabled: true))
        m.launch(observed: false, power: battery(80))
        #expect(m.engine.update(power: ac, now: t0) == [.saveRecord, .apply(sleepDisabled: true, interactive: false)])
        let after = m.finish(.done, observed: false, worked: true)
        #expect(after == [.saveRecord])
        #expect(m.status == .needsYou && !m.engine.record.ownsSleepDisabled)
        #expect(m.engine.note == .failed("macOS kept SleepDisabled at 0"))
        #expect(m.model.detail == "That didn't work: macOS kept SleepDisabled at 0")
        #expect(m.engine.update(power: PowerSnapshot(onAC: true, batteryPercent: 81), now: t0).isEmpty)

        // The same for putting sleep back: no straight-back loop, one try per fact.
        let r = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        r.launch(observed: true)
        _ = r.engine.update(power: battery(50), now: t0)
        #expect(r.finish(.done, observed: true).isEmpty)
        #expect(r.status == .stillOff && r.engine.restorePending)
        #expect(r.engine.update(power: battery(49), now: t0) == [.apply(sleepDisabled: false, interactive: true)])
    }

    @Test("a failed change whose result can't be read keeps the record it had")
    func unreadableFailure() {
        let m = Machine(LidAwakeSettings(enabled: true))
        m.launch(observed: false, power: battery(80))
        _ = m.engine.update(power: ac, now: t0)
        #expect(m.engine.record.ownsSleepDisabled)
        m.finish(.failed("timed out"), observed: .some(nil), worked: false)
        #expect(!m.engine.record.ownsSleepDisabled)
    }

    @Test("an outside SleepDisabled 1 is adopted (switch on, guards passing) only through a working helper")
    func adoptOutside() {
        let m = Machine(LidAwakeSettings(enabled: true))
        #expect(m.launch(observed: true, probeWorks: nil) == [.saveRecord, .apply(sleepDisabled: true, interactive: false)])
        m.finish(worked: true)
        #expect(m.status == .awake && m.engine.record.ownsSleepDisabled)

        // Refused: not adopted, not touched.
        let r = Machine(LidAwakeSettings(enabled: true))
        _ = r.launch(observed: true, probeWorks: nil)
        #expect(r.finish(.failed("sudo: a password is required"), worked: false) == [.saveRecord])
        #expect(!r.engine.record.ownsSleepDisabled && r.engine.sleepDisabled && r.status == .outside)
    }

    @Test("a fresh read re-checks the helper while the switch is on, at most every ten minutes")
    func probeOnRefresh() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true)
        #expect(m.engine.update(observed: true, helperInstalled: true, now: at(60)).isEmpty)
        #expect(m.engine.update(observed: true, helperInstalled: true, now: at(601)) == [.apply(sleepDisabled: true, interactive: false)])
        m.finish(worked: true, now: at(601))
        // Off: never probed.
        let off = Machine()
        off.launch(observed: false)
        #expect(off.engine.update(observed: false, helperInstalled: true, now: at(9999)).isEmpty)
    }

    @Test("the helper's file gone while kept awake: normal sleep goes back")
    func helperFileGone() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true)
        #expect(m.engine.update(observed: true, helperInstalled: false, now: at(60)) == [.apply(sleepDisabled: false, interactive: true)])
    }

    // MARK: The helper

    @Test("removing the helper while awake puts sleep back in the same dialog and turns the switch off")
    func removeHelper() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true)
        #expect(m.engine.removeHelper(now: t0) == [.removeHelper(thenSleepDisabled: false)])
        #expect(m.status == .switching(.removing))
        let after = m.finish()
        #expect(after.contains(.saveRecord) && after.contains(.saveSettings) && !after.contains(.nudgeSleep))
        #expect(!m.engine.settings.enabled && !m.engine.helperInstalled && m.status == .normal)
    }

    @Test("removing it cancelled changes nothing")
    func removeCancelled() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true)
        _ = m.engine.removeHelper(now: t0)
        #expect(m.finish(.cancelled, observed: true).isEmpty)
        #expect(m.engine.settings.enabled && m.status == .awake && m.engine.helperInstalled)
    }

    // MARK: Quit

    @Test("quit puts sleep back unless “keep after quit” is on and the guards still want it awake")
    func quit() {
        let m = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        m.launch(observed: true)
        #expect(m.engine.shouldRestoreOnQuit(now: t0))

        let keep = Machine(LidAwakeSettings(enabled: true, keepAfterQuit: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        keep.launch(observed: true)
        #expect(!keep.engine.shouldRestoreOnQuit(now: t0))
        // The clock has run out: quitting puts it back anyway.
        let expired = Machine(LidAwakeSettings(enabled: true, autoOffHours: 1, keepAfterQuit: true, clockStart: t0),
                              record: LidAwakeRecord(ownsSleepDisabled: true))
        expired.launch(observed: true)
        #expect(expired.engine.shouldRestoreOnQuit(now: at(3700)))

        // Not NotchHub's: never touched at quit.
        let outside = Machine()
        outside.launch(observed: true)
        #expect(!outside.engine.shouldRestoreOnQuit(now: t0))

        #expect(m.engine.quitRestored(outcome: .done, observed: false) == [.saveRecord])
        #expect(m.engine.record == LidAwakeRecord())
        // A failed quit restore keeps the record for the next launch.
        let failed = Machine(LidAwakeSettings(enabled: true), record: LidAwakeRecord(ownsSleepDisabled: true))
        failed.launch(observed: true)
        #expect(failed.engine.quitRestored(outcome: .cancelled, observed: true).isEmpty)
        #expect(failed.engine.record.ownsSleepDisabled)
    }

    @Test("quit with a turn-on still in flight: the record (written first) says restore, whatever the cached read")
    func quitWhileTurningOn() {
        let m = Machine(LidAwakeSettings(enabled: true))
        m.launch(observed: false, power: battery(80))
        _ = m.engine.update(power: ac, now: t0)
        #expect(m.engine.busy && m.engine.observed == false)
        #expect(m.engine.shouldRestoreOnQuit(now: t0))
        // Keep after quit, guards passing: left on by choice.
        let keep = Machine(LidAwakeSettings(enabled: true, keepAfterQuit: true))
        keep.launch(observed: false, power: battery(80))
        _ = keep.engine.update(power: ac, now: t0)
        #expect(!keep.engine.shouldRestoreOnQuit(now: t0))
    }

    // MARK: The page

    @Test("the status lines")
    func lines() {
        func model(_ status: LidSettingsModel.Status, _ settings: LidAwakeSettings = LidAwakeSettings(enabled: true)) -> LidSettingsModel {
            LidSettingsModel(settings: settings, status: status, helperInstalled: true)
        }
        #expect(model(.awake).headline == "Your Mac will keep working with the lid closed")
        #expect(model(.normal, LidAwakeSettings()).headline == "Normal sleep")
        #expect(model(.held(.onBattery)).headline == "Paused: on battery")
        #expect(model(.held(.appsClosed)).headline == "Paused: none of your apps is open")
        #expect(model(.held(.noAppsChosen)).headline == "Paused: no apps chosen")
        #expect(model(.outside).headline == "Sleep is turned off outside NotchHub")
        #expect(model(.awake).shortLabel == "On — keeps working when closed")
        #expect(model(.normal, LidAwakeSettings()).shortLabel == "Off — sleeps when closed")
    }

    @Test("what can be tapped: the floor only without the adapter guard; nothing while busy or unmanaged")
    func enabled() {
        let on = LidSettingsModel(settings: LidAwakeSettings(enabled: true), status: .awake, helperInstalled: true)
        #expect(!on.isEnabled(.batteryFloor(25)))
        #expect(LidSettingsModel(settings: LidAwakeSettings(enabled: true, onlyOnPower: false), status: .awake).isEnabled(.batteryFloor(25)))
        #expect(on.isEnabled(.removeHelper) && !on.isEnabled(.installHelper) && !on.isEnabled(.resume))
        #expect(!LidSettingsModel(settings: LidAwakeSettings(), status: .switching(.on), busy: true).isEnabled(.setEnabled(false)))
        #expect(!LidSettingsModel(status: .notManaged).isEnabled(.setEnabled(true)))
    }
}
