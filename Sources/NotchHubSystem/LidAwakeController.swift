import AppKit
import CoreGraphics
import IOKit
import IOKit.ps
import NotchHubCore

// "Keep working with the lid closed": the system half. The decisions are
// `LidAwakeEngine`'s (NotchHubCore); this file watches the power and the apps,
// runs the commands the engine asks for, and reports back. Nothing here
// touches UI state: the app coordinator reads `model` when `onChange` fires.

// MARK: - Seams (faked in tests)

/// How a privileged command went.
public enum PrivilegedResult: Equatable, Sendable {
    case ok
    /// The admin dialog was cancelled.
    case cancelled
    case failed(String)

    var outcome: LidAwakeOutcome {
        switch self {
        case .ok: return .done
        case .cancelled: return .cancelled
        case let .failed(why): return .failed(why)
        }
    }
}

/// The only two ways anything runs as root. Both block; the controller
/// calls them off the main thread (except the helper at quit).
public protocol PrivilegedRunner: Sendable {
    /// `sudo -n /usr/bin/pmset -a disablesleep 0|1` through the helper
    /// rule. Never prompts: without the rule it fails at once.
    func runWithHelper(sleepDisabled: Bool) -> PrivilegedResult
    /// A shell script as root through macOS's own admin dialog (AppleScript
    /// `do shell script … with administrator privileges`). NotchHub never
    /// sees the password.
    func runAsAdmin(script: String, prompt: String) -> PrivilegedResult
    /// NotchHub is quitting: stop the command running now (a password dialog
    /// nobody will answer now, a helper command) — the blocked call returns a
    /// failure — and show no password dialog from now on. The helper stays
    /// usable: the quit restore goes through it.
    func cancelRunning()
}

extension PrivilegedRunner {
    public func cancelRunning() {}
}

/// The Mac's power source, and word when it changes.
public protocol PowerSource: AnyObject {
    func snapshot() -> PowerSnapshot?
    func startObserving(_ onChange: @escaping () -> Void)
    func stopObserving()
}

/// The running apps (by bundle identifier), and word when one opens or
/// quits — and when the Mac wakes.
public protocol Workspace: AnyObject {
    func runningBundleIDs() -> Set<String>
    func startObserving(appsChanged: @escaping () -> Void, didWake: @escaping () -> Void)
    func stopObserving()
}

/// What can be read, and asked, without root.
public protocol LidSystem: Sendable {
    /// `SleepDisabled` from `pmset -g` (`nil` if the read failed).
    func sleepDisabled() -> Bool?
    /// Whether the helper rule's file is there (its content is root's to read).
    func helperInstalled() -> Bool
    /// IOPMrootDomain's `AppleClamshellState` (`nil` if unreadable).
    func lidClosed() -> Bool?
    /// Any display online that is not the built-in one.
    func externalDisplayConnected() -> Bool
    /// `pmset sleepnow` (the console user may ask for sleep).
    func sleepNow()
}

/// Something scheduled that can be called off.
public protocol LidCancellable: AnyObject {
    func cancel()
}

/// The dead-man's switch: while armed, if NotchHub dies without a clean quit
/// (a crash, Force Quit, `kill -9`), normal sleep is put back through the
/// helper. Arming and disarming are idempotent.
public protocol LidWatchdog: AnyObject {
    func arm()
    func disarm()
}

// MARK: - The controller

/// Keeps the Mac awake with the lid closed — and, above all, puts normal
/// sleep back whenever it should.
///
/// - **Launch** (`start`): reads `pmset -g`, the power and the apps, and lets
///   the engine reconcile: a `SleepDisabled 1` NotchHub left behind (a crash,
///   a kill) is put back unless the switch and the guards still want it.
/// - **While running**: IOKit power-source notifications, NSWorkspace app
///   launches / quits and wakes, and the auto-off clock feed the engine; the
///   commands it asks for run one at a time off the main thread.
/// - **Quit** (`prepareForQuit`, from `applicationWillTerminate`): a command
///   still running is stopped, and normal sleep goes back synchronously
///   through the helper — never a dialog at quit — unless "Keep after
///   NotchHub quits" is on and the guards still want the Mac awake.
/// - **A crash** (or Force Quit): a dead-man's switch (`LidWatchdog`), armed
///   whenever NotchHub's going away should put sleep back, does it.
/// - **A guard putting sleep back** while the lid is closed with no external
///   display: if macOS has not slept on its own a little later, it is asked
///   to (`pmset sleepnow`, no root) — a closed Mac in a bag must not stay up
///   because the setting changed after the lid did.
/// - **A restore that fails** is retried through the helper every minute
///   (`restoreRetryInterval`) and on every fact; the admin dialog is shown
///   for it at most once per hold, and never while the lid is closed.
///
/// While NotchHub holds `SleepDisabled 1` it also holds an activity that
/// keeps App Nap from slowing its timers with the lid shut.
@MainActor
public final class LidAwakeController {

    public private(set) var engine: LidAwakeEngine
    /// `start` has run: the switch is live.
    public private(set) var isRunning = false
    /// Fires when what Settings → Lid shows changes.
    public var onChange: (() -> Void)?

    private let runner: PrivilegedRunner
    private let power: PowerSource
    private let workspace: Workspace
    private let system: LidSystem
    private let defaults: UserDefaults
    private let userName: String
    private let clock: () -> Date
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> LidCancellable
    private let background: (@escaping @Sendable () -> Void) -> Void
    private let holdsActivity: Bool
    private let watchdog: LidWatchdog
    private let readbackDelay: TimeInterval
    private let quitWait: TimeInterval

    private var deadlineTimer: LidCancellable?
    private var nudgeTimer: LidCancellable?
    private var retryTimer: LidCancellable?
    private var activity: NSObjectProtocol?
    private var lastModel: LidSettingsModel?
    /// Entered while a command runs off the main thread; quitting waits on it.
    private let commands = DispatchGroup()

    /// How long after a guard puts sleep back the lid is checked (macOS may
    /// well have slept on its own by then; if so this runs after the wake and
    /// finds the lid open, or the Mac asleep again harmlessly).
    public static let nudgeDelay: TimeInterval = 20
    /// How often a restore that has not landed is tried again.
    public static let restoreRetryInterval: TimeInterval = 60

    public init(
        runner: PrivilegedRunner = SystemPrivilegedRunner(),
        power: PowerSource = IOKitPowerSource(),
        workspace: Workspace = SystemWorkspace(),
        system: LidSystem = SystemLid(),
        defaults: UserDefaults = .standard,
        userName: String = NSUserName(),
        clock: @escaping () -> Date = Date.init,
        schedule: ((TimeInterval, @escaping @MainActor () -> Void) -> LidCancellable)? = nil,
        background: ((@escaping @Sendable () -> Void) -> Void)? = nil,
        holdsActivity: Bool = true,
        watchdog: LidWatchdog = ProcessWatchdog(),
        readbackDelay: TimeInterval = 1,
        quitWait: TimeInterval = 5
    ) {
        self.runner = runner
        self.power = power
        self.workspace = workspace
        self.system = system
        self.defaults = defaults
        self.userName = userName
        self.clock = clock
        self.schedule = schedule ?? { seconds, block in TimerCancellable(after: seconds, block) }
        self.background = background ?? { work in DispatchQueue.global(qos: .userInitiated).async(execute: work) }
        self.holdsActivity = holdsActivity
        self.watchdog = watchdog
        self.readbackDelay = readbackDelay
        self.quitWait = quitWait
        engine = LidAwakeEngine(
            settings: LidAwakeSettings.load(from: defaults),
            record: LidAwakeRecord.load(from: defaults),
            helperInstalled: system.helperInstalled()
        )
    }

    /// What Settings → Lid shows.
    public var model: LidSettingsModel { LidSettingsModel(engine: engine, managed: isRunning) }

    // MARK: Lifecycle

    /// Starts watching, and reconciles what `pmset -g` says with NotchHub's
    /// record and the guards (the crash case).
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        power.startObserving { [weak self] in
            MainActor.assumeIsolated { self?.powerChanged() }
        }
        workspace.startObserving(
            appsChanged: { [weak self] in MainActor.assumeIsolated { self?.appsChanged() } },
            didWake: { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        )
        let system = self.system
        offMain({ (system.sleepDisabled(), system.helperInstalled()) }) { [weak self] read in
            guard let self, self.isRunning else { return }
            self.perform(self.engine.launch(
                observed: read.0, power: self.power.snapshot(), running: self.workspace.runningBundleIDs(),
                helperInstalled: read.1, now: self.clock()
            ))
        }
    }

    /// Re-reads `pmset -g` and the helper (the Mac woke, or the page opened),
    /// so the status is the system's, not a memory of it.
    public func refresh() {
        guard isRunning else { return }
        let system = self.system
        offMain({ (system.sleepDisabled(), system.helperInstalled()) }) { [weak self] read in
            guard let self, self.isRunning else { return }
            var effects = self.engine.update(power: self.power.snapshot(), now: self.clock())
            effects += self.engine.update(observed: read.0, helperInstalled: read.1, now: self.clock())
            self.perform(effects)
        }
    }

    /// NotchHub is quitting: put normal sleep back now (synchronously),
    /// unless the user asked to keep it and the guards still want it.
    ///
    /// A command still in flight is stopped first (a password dialog closed,
    /// a helper command given `quitWait` to land), so nothing it started can
    /// change the Mac once NotchHub is gone; then `pmset -g` is read afresh —
    /// the cached value may be from before that command. Only the helper is
    /// used: a password dialog during a quit (or a logout) could hold it for
    /// minutes. If the helper fails, the record stays for the next launch.
    public func prepareForQuit() {
        guard isRunning else { return }
        isRunning = false
        power.stopObserving()
        workspace.stopObserving()
        deadlineTimer?.cancel()
        nudgeTimer?.cancel()
        retryTimer?.cancel()
        retryTimer = nil
        defer {
            endActivity()
            // A clean quit: whatever was due is done (or left to the next
            // launch, which reconciles), so the dead-man's switch stands down.
            watchdog.disarm()
        }
        if engine.busy {
            runner.cancelRunning()
            _ = commands.wait(timeout: .now() + quitWait)
        }
        guard engine.shouldRestoreOnQuit(now: clock()) else { return }
        let fresh = system.sleepDisabled()
        var result: PrivilegedResult = .ok
        if fresh != false {
            result = system.helperInstalled() ? runner.runWithHelper(sleepDisabled: false) : .failed("The helper isn't set up.")
        }
        let after = fresh == false ? false : system.sleepDisabled()
        for effect in engine.quitRestored(outcome: result.outcome, observed: after) where effect == .saveRecord {
            engine.record.save(to: defaults)
        }
    }

    // MARK: The page

    /// A tap in Settings → Lid (`.chooseApp` is the app's: it opens a panel
    /// and comes back with `.addApp`).
    public func handle(_ intent: LidIntent) {
        guard isRunning else { return }
        let now = clock()
        let effects: [LidAwakeEffect]
        switch intent {
        case let .setEnabled(on): effects = engine.setEnabled(on, now: now)
        case let .onlyOnPower(on): effects = engine.change(now: now) { $0.onlyOnPower = on }
        case let .batteryFloor(floor): effects = engine.change(now: now) { $0.batteryFloor = floor }
        case let .onlyWhileApps(on): effects = engine.change(now: now) { $0.onlyWhileApps = on }
        case let .addApp(bundleID): effects = engine.change(now: now) { $0.addApp(bundleID) }
        case let .removeApp(bundleID): effects = engine.change(now: now) { $0.removeApp(bundleID) }
        case let .autoOff(hours): effects = engine.change(now: now) { $0.autoOffHours = hours }
        case let .keepAfterQuit(on): effects = engine.change(now: now) { $0.keepAfterQuit = on }
        case .installHelper: effects = engine.installHelper(now: now)
        case .removeHelper: effects = engine.removeHelper(now: now)
        case .resume: effects = engine.resume(now: now)
        case .restoreNormalSleep: effects = engine.restoreNormalSleep(now: now)
        case .chooseApp: return
        }
        perform(effects)
    }

    // MARK: Facts

    private func powerChanged() {
        guard isRunning else { return }
        perform(engine.update(power: power.snapshot(), now: clock()))
    }

    private func appsChanged() {
        guard isRunning else { return }
        perform(engine.update(running: workspace.runningBundleIDs(), now: clock()))
    }

    /// The auto-off deadline, or a restore's retry.
    private func tick() {
        guard isRunning else { return }
        perform(engine.tick(now: clock()))
    }

    // MARK: Effects

    private func perform(_ effects: [LidAwakeEffect]) {
        for effect in effects {
            switch effect {
            case .saveSettings: engine.settings.save(to: defaults)
            // Saved before the command it precedes is even started.
            case .saveRecord: engine.record.save(to: defaults)
            case .nudgeSleep: scheduleNudge()
            case .apply, .installHelper, .removeHelper: run(effect)
            }
        }
        scheduleDeadline()
        scheduleRetry()
        syncActivity()
        syncWatchdog()
        let model = self.model
        if model != lastModel {
            lastModel = model
            onChange?()
        }
    }

    /// What a command did, for `LidAwakeEngine.finished`.
    private struct Report: Sendable {
        var outcome: LidAwakeOutcome
        var observed: Bool?
        var helperWorked: Bool?
        var helperInstalled: Bool
        var askedAdmin: Bool
    }

    private func run(_ effect: LidAwakeEffect) {
        let runner = self.runner
        let system = self.system
        let rule = LidAwakeHelperRule(user: userName)
        let readbackDelay = self.readbackDelay
        let commands = self.commands
        // A person at the page may be shown the dialog to put sleep back
        // whatever the lid; the guards on their own never to a closed one.
        let attended = engine.inFlight.map { $0.cause == .user || $0.cause == .settings } ?? false
        commands.enter()
        offMain({ () -> Report in
            defer { commands.leave() }
            var helperWorked: Bool?
            var askedAdmin = false
            let outcome: LidAwakeOutcome
            switch effect {
            case let .apply(value, interactive):
                var result: PrivilegedResult = .failed("The helper isn't set up.")
                if system.helperInstalled() {
                    result = runner.runWithHelper(sleepDisabled: value)
                    helperWorked = result == .ok
                }
                // Only putting sleep BACK may fall back on the dialog: the Mac
                // is never kept awake without the helper's silent way back.
                if result != .ok, interactive, !value, attended || system.lidClosed() != true {
                    askedAdmin = true
                    result = runner.runAsAdmin(script: LidAwakeCommands.pmsetLine(sleepDisabled: false), prompt: LidAwakePrompt.sleep)
                }
                outcome = result.outcome
            case .installHelper:
                if let rule {
                    outcome = runner.runAsAdmin(script: rule.installScript(), prompt: LidAwakePrompt.install).outcome
                } else {
                    outcome = .failed("your account name can't be used in a sudoers rule")
                }
            case let .removeHelper(then):
                askedAdmin = then == false
                outcome = runner.runAsAdmin(script: LidAwakeHelperRule.uninstallScript(thenSleepDisabled: then),
                                            prompt: LidAwakePrompt.remove).outcome
            case .saveSettings, .saveRecord, .nudgeSleep:
                outcome = .done
            }
            var observed = system.sleepDisabled()
            // pmset's own read can trail a change by a moment: one more look
            // before a "worked" change is taken for one that didn't.
            if outcome == .done, let target = effect.target, let read = observed, read != target, readbackDelay > 0 {
                Thread.sleep(forTimeInterval: readbackDelay)
                observed = system.sleepDisabled()
            }
            return Report(outcome: outcome, observed: observed, helperWorked: helperWorked,
                          helperInstalled: system.helperInstalled(), askedAdmin: askedAdmin)
        }) { [weak self] report in
            // After quit the engine is done: a late answer changes nothing.
            guard let self, self.isRunning else { return }
            self.perform(self.engine.finished(
                outcome: report.outcome, observed: report.observed, helperInstalled: report.helperInstalled,
                helperWorked: report.helperWorked, askedAdmin: report.askedAdmin, now: self.clock()
            ))
        }
    }

    /// The auto-off clock: a timer at the deadline (every evaluation also
    /// checks it, so a late timer after a sleep is still on time).
    private func scheduleDeadline() {
        deadlineTimer?.cancel()
        deadlineTimer = nil
        guard isRunning, let deadline = engine.settings.autoOffDeadline else { return }
        let delay = max(0, deadline.timeIntervalSince(clock())) + 0.25
        deadlineTimer = schedule(delay) { [weak self] in self?.tick() }
    }

    /// A restore that has not landed is tried again every minute (each try
    /// is the helper; the dialog only as the engine allows).
    private func scheduleRetry() {
        guard isRunning, engine.restorePending, !engine.busy else {
            retryTimer?.cancel()
            retryTimer = nil
            return
        }
        guard retryTimer == nil else { return }
        retryTimer = schedule(Self.restoreRetryInterval) { [weak self] in
            self?.retryTimer = nil
            self?.tick()
        }
    }

    /// Armed whenever NotchHub vanishing now should put normal sleep back.
    private func syncWatchdog() {
        guard isRunning else { return }
        if engine.shouldRestoreOnQuit(now: clock()) {
            watchdog.arm()
        } else {
            watchdog.disarm()
        }
    }

    private func scheduleNudge() {
        nudgeTimer?.cancel()
        nudgeTimer = schedule(Self.nudgeDelay) { [weak self] in self?.nudge() }
    }

    /// Normal sleep is back because a guard said so: if the lid is closed
    /// with no external display (so nobody can be using this Mac) and macOS
    /// has not slept on its own, ask it to.
    private func nudge() {
        nudgeTimer = nil
        guard isRunning, !engine.busy, !engine.sleepDisabled, engine.verdict != .awake else { return }
        let system = self.system
        offMain({ () -> Bool in
            guard system.lidClosed() == true, !system.externalDisplayConnected() else { return false }
            system.sleepNow()
            return true
        }) { _ in }
    }

    private func syncActivity() {
        guard holdsActivity else { return }
        if engine.isKeepingAwake, isRunning {
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep,
                    reason: "Keeping the Mac working with the lid closed"
                )
            }
        } else {
            endActivity()
        }
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    /// Runs `work` off the main thread, then `done` on it.
    private func offMain<T>(_ work: @escaping @Sendable () -> T, _ done: @escaping @MainActor (T) -> Void) {
        let box = ResultBox<T>()
        background {
            box.value = work()
            if Thread.isMainThread {
                MainActor.assumeIsolated { if let value = box.value { done(value) } }
            } else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { if let value = box.value { done(value) } }
                }
            }
        }
    }
}

/// The words in macOS's password dialog (after its own "NotchHub wants to
/// make changes" line, osascript shows this prompt).
enum LidAwakePrompt {
    static let sleep = "NotchHub wants to put your Mac's normal sleep back."
    static let install = "NotchHub wants to keep your Mac working with the lid closed. "
        + "This lets it switch only that setting from now on without asking again."
    static let remove = "NotchHub wants to remove its lid-closed helper and put your Mac's normal sleep back."
}

/// Carries a value from the background closure to the main-thread one.
private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

private final class TimerCancellable: LidCancellable {
    private var timer: Timer?

    init(after seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { block() }
        }
        timer.tolerance = min(1, seconds * 0.05)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - The real system

/// Runs a command-line tool with a timeout, collecting its output.
enum CommandLineTool {
    struct Result: Sendable {
        var status: Int32
        var output: String
        var error: String
        var timedOut: Bool
    }

    /// - Parameter track: told of the process once it runs, and of its end
    ///   (`nil`), so it can be stopped from elsewhere.
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval,
                    track: ((Process?) -> Void)? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "", error: error.localizedDescription, timedOut: false)
        }
        track?(process)
        defer { track?(nil) }
        // Read while it runs, so a full pipe can never stall it.
        let readers = DispatchGroup()
        let outBox = ResultBox<Data>()
        let errBox = ResultBox<Data>()
        DispatchQueue.global().async(group: readers) { outBox.value = out.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global().async(group: readers) { errBox.value = err.fileHandleForReading.readDataToEndOfFile() }
        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            _ = exited.wait(timeout: .now() + 2)
        }
        _ = readers.wait(timeout: .now() + 2)
        return Result(
            status: timedOut ? -1 : process.terminationStatus,
            output: String(decoding: outBox.value ?? Data(), as: UTF8.self),
            error: String(decoding: errBox.value ?? Data(), as: UTF8.self),
            timedOut: timedOut
        )
    }

    /// The last non-empty line of an error, trimmed for a status line.
    static func shortError(_ text: String, fallback: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return fallback }
        return line.count > 90 ? String(line.prefix(89)) + "…" : line
    }
}

/// `sudo -n` with the helper rule, and `osascript` for the admin dialog.
public final class SystemPrivilegedRunner: PrivilegedRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Process?
    private var quitting = false

    public init() {}

    public func runWithHelper(sleepDisabled: Bool) -> PrivilegedResult {
        let result = CommandLineTool.run(LidAwakeCommands.sudo, LidAwakeCommands.sudoArguments(sleepDisabled: sleepDisabled),
                                         timeout: 15, track: { [self] in track($0, dialog: false) })
        if result.status == 0 { return .ok }
        return .failed(CommandLineTool.shortError(result.error, fallback: "sudo refused the helper rule"))
    }

    public func runAsAdmin(script: String, prompt: String) -> PrivilegedResult {
        guard !isQuitting else { return .failed("NotchHub is quitting") }
        let source = AppleScriptSource.adminShellScript(script, prompt: prompt)
        // Long enough for someone to type a password; not forever.
        let result = CommandLineTool.run(LidAwakeCommands.osascript, ["-e", source], timeout: 300,
                                         track: { [self] in track($0, dialog: true) })
        if result.status == 0 { return .ok }
        if AppleScriptSource.isUserCancel(result.error) { return .cancelled }
        if result.timedOut { return .failed("the password prompt timed out") }
        return .failed(CommandLineTool.shortError(result.error, fallback: "the command failed"))
    }

    /// Stops the command running now (SIGTERM: osascript closes its dialog,
    /// sudo passes it on), and refuses any password dialog after.
    public func cancelRunning() {
        lock.lock()
        quitting = true
        let process = current
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    private var isQuitting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return quitting
    }

    private func track(_ process: Process?, dialog: Bool) {
        lock.lock()
        current = process
        let stop = quitting && dialog
        lock.unlock()
        // A dialog launched between the check and `cancelRunning`.
        if stop, let process, process.isRunning { process.terminate() }
    }
}

/// The dead-man's switch as a process: `/bin/sh` running
/// `LidAwakeCommands.watchdogScript`, outside NotchHub so it outlives a
/// crash. Not waited on; stopped with SIGTERM.
public final class ProcessWatchdog: LidWatchdog {
    private let pid: Int32
    private let processName: String
    private let restore: String
    private let interval: Double
    private var process: Process?

    /// - Parameters:
    ///   - pid: the process whose end triggers the restore (NotchHub's own)
    ///   - restore: the command run then (the helper's `disablesleep 0`)
    public init(pid: Int32 = ProcessInfo.processInfo.processIdentifier,
                processName: String = ProcessInfo.processInfo.processName,
                restore: String = LidAwakeCommands.helperRestoreLine,
                interval: Double = 5) {
        self.pid = pid
        self.processName = processName
        self.restore = restore
        self.interval = interval
    }

    public var isArmed: Bool { process?.isRunning == true }

    public func arm() {
        guard !isArmed else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", LidAwakeCommands.watchdogScript(
            pid: pid, uid: getuid(), processName: processName, interval: interval, restore: restore
        )]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            self.process = process
        } catch {
            self.process = nil
        }
    }

    public func disarm() {
        if let process, process.isRunning { process.terminate() }
        process = nil
    }
}

/// `pmset -g`, the helper's file, the clamshell, the displays, `pmset sleepnow`.
public struct SystemLid: LidSystem {
    public init() {}

    public func sleepDisabled() -> Bool? {
        let result = CommandLineTool.run(LidAwakeCommands.pmset, LidAwakeCommands.readArguments, timeout: 10)
        guard result.status == 0 else { return nil }
        return LidAwakeCommands.sleepDisabled(inPmsetOutput: result.output)
    }

    public func helperInstalled() -> Bool {
        FileManager.default.fileExists(atPath: LidAwakeHelperRule.path)
    }

    public func lidClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return value as? Bool
    }

    public func externalDisplayConnected() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    public func sleepNow() {
        _ = CommandLineTool.run(LidAwakeCommands.pmset, LidAwakeCommands.sleepNowArguments, timeout: 10)
    }
}

/// IOKit power sources: the providing source and the internal battery.
public final class IOKitPowerSource: PowerSource {
    private var runLoopSource: CFRunLoopSource?
    private var onChange: (() -> Void)?

    public init() {}

    public func snapshot() -> PowerSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        var descriptions: [[String: Any]] = []
        if let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] {
                    descriptions.append(description)
                }
            }
        }
        return Self.snapshot(providing: providing, descriptions: descriptions)
    }

    /// The snapshot from IOKit's dictionaries: on AC when the providing
    /// source is the adapter (or a UPS); the charge from the internal battery.
    static func snapshot(providing: String?, descriptions: [[String: Any]]) -> PowerSnapshot? {
        guard let providing else { return nil }
        let onAC = providing == kIOPMACPowerKey || providing == kIOPMUPSPowerKey
        var percent: Int?
        for description in descriptions where (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType {
            guard let current = description[kIOPSCurrentCapacityKey] as? Int else { continue }
            let maximum = (description[kIOPSMaxCapacityKey] as? Int) ?? 100
            percent = maximum > 0 ? Int((Double(current) * 100 / Double(maximum)).rounded()) : current
            break
        }
        return PowerSnapshot(onAC: onAC, batteryPercent: percent)
    }

    public func startObserving(_ onChange: @escaping () -> Void) {
        guard runLoopSource == nil else { return }
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            Unmanaged<IOKitPowerSource>.fromOpaque(ctx).takeUnretainedValue().onChange?()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            // Common modes: a power change is heard while a menu is open too.
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    public func stopObserving() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        onChange = nil
    }

    deinit { stopObserving() }
}

/// NSWorkspace: running apps, launches, quits and wakes.
///
/// Launches and quits come from the running-applications list's KVO as well
/// as the launch / terminate notifications: macOS posts those notifications
/// only for ordinary apps, so a chosen menu-bar or agent app (LSUIElement)
/// quitting would otherwise go unheard. The engine ignores a repeat.
public final class SystemWorkspace: Workspace {
    private let workspace: NSWorkspace
    private var observers: [NSObjectProtocol] = []
    private var listObserver: RunningAppsObserver?

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func runningBundleIDs() -> Set<String> {
        Set(workspace.runningApplications.compactMap(\.bundleIdentifier))
    }

    public func startObserving(appsChanged: @escaping () -> Void, didWake: @escaping () -> Void) {
        guard observers.isEmpty else { return }
        let center = workspace.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in appsChanged() })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in didWake() })
        listObserver = RunningAppsObserver(workspace: workspace, onChange: appsChanged)
    }

    public func stopObserving() {
        let center = workspace.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        listObserver?.stop()
        listObserver = nil
    }

    deinit { stopObserving() }
}

/// KVO on `NSWorkspace.runningApplications` (documented as observable),
/// delivered on the main thread.
private final class RunningAppsObserver: NSObject {
    private static let key = "runningApplications"
    private var workspace: NSWorkspace?
    private let onChange: () -> Void

    init(workspace: NSWorkspace, onChange: @escaping () -> Void) {
        self.workspace = workspace
        self.onChange = onChange
        super.init()
        workspace.addObserver(self, forKeyPath: Self.key, options: [.new], context: nil)
    }

    func stop() {
        workspace?.removeObserver(self, forKeyPath: Self.key)
        workspace = nil
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == Self.key else { return }
        if Thread.isMainThread {
            onChange()
        } else {
            let onChange = self.onChange
            DispatchQueue.main.async { onChange() }
        }
    }

    deinit { stop() }
}
