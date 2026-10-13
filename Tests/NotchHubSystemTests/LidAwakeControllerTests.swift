import AppKit
import Foundation
import Testing
import NotchHubCore
@testable import NotchHubSystem

// Nothing here runs as root or changes this Mac: the privileged runner, the
// power source, the workspace, the system reads and the dead-man's switch
// are all fakes over one pretend Mac. (The last suites only READ — `pmset
// -g`, IOKit — or run harmless stand-ins: `sleep`, `touch`.)

/// The pretend Mac the fakes share.
private final class FakeMac: @unchecked Sendable {
    var sleepDisabled = false
    var helperFile = false
    /// `sudo -n` honours the rule.
    var helperWorks = true
    /// What the admin dialog does: `.ok` runs the script.
    var adminAnswer: PrivilegedResult = .ok
    var lidClosed: Bool? = false
    var externalDisplay = false
    var sleepNowCount = 0
    var calls: [String] = []
    /// The record in the defaults at the moment each command started.
    var recordAtCall: [Bool] = []
    var defaults: UserDefaults?
    /// `cancelRunning` was called (NotchHub quitting): no more dialogs.
    var cancelled = false
    /// Inside `cancelRunning`: the command running now is being stopped.
    var terminating = false
    /// Run by `cancelRunning` while `terminating`: the in-flight work
    /// finishing, as a stopped command lets it.
    var onCancel: (() -> Void)?
    /// Whether sudo honours the rule once installed (`false`: the drop-in
    /// directory isn't included by this Mac's sudoers).
    var sudoReadsDropIns = true
}

private struct FakeRunner: PrivilegedRunner {
    let mac: FakeMac

    func runWithHelper(sleepDisabled: Bool) -> PrivilegedResult {
        note("sudo -n pmset \(sleepDisabled ? 1 : 0)")
        guard !mac.terminating else { return .failed("terminated") }
        guard mac.helperFile, mac.helperWorks else { return .failed("sudo: a password is required") }
        mac.sleepDisabled = sleepDisabled
        return .ok
    }

    func runAsAdmin(script: String, prompt: String) -> PrivilegedResult {
        note("admin: \(script)")
        guard !mac.cancelled, !mac.terminating else { return .failed("NotchHub is quitting") }
        guard mac.adminAnswer == .ok else { return mac.adminAnswer }
        // The script's effects, in order.
        for step in script.components(separatedBy: "; ") {
            if step == LidAwakeCommands.pmsetLine(sleepDisabled: true) { mac.sleepDisabled = true }
            if step == LidAwakeCommands.pmsetLine(sleepDisabled: false) { mac.sleepDisabled = false }
            if step.hasPrefix("/bin/mv -f \"$t\" \(LidAwakeHelperRule.path)") { mac.helperFile = true; mac.helperWorks = mac.sudoReadsDropIns }
            if step == "/bin/rm -f \(LidAwakeHelperRule.path)" { mac.helperFile = false }
        }
        return .ok
    }

    func cancelRunning() {
        mac.calls.append("cancel")
        mac.cancelled = true
        mac.terminating = true
        mac.onCancel?()
        mac.terminating = false
    }

    private func note(_ call: String) {
        mac.calls.append(call)
        mac.recordAtCall.append(mac.defaults.map { LidAwakeRecord.load(from: $0).ownsSleepDisabled } ?? false)
    }
}

private struct FakeLid: LidSystem {
    let mac: FakeMac
    func sleepDisabled() -> Bool? { mac.sleepDisabled }
    func helperInstalled() -> Bool { mac.helperFile }
    func lidClosed() -> Bool? { mac.lidClosed }
    func externalDisplayConnected() -> Bool { mac.externalDisplay }
    func sleepNow() { mac.sleepNowCount += 1 }
}

private final class FakePower: PowerSource {
    var current: PowerSnapshot? = PowerSnapshot(onAC: true, batteryPercent: 80)
    var onChange: (() -> Void)?
    func snapshot() -> PowerSnapshot? { current }
    func startObserving(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    func stopObserving() { onChange = nil }
    func set(_ snapshot: PowerSnapshot?) {
        current = snapshot
        onChange?()
    }
}

private final class FakeWorkspace: Workspace {
    var running: Set<String> = ["com.apple.finder"]
    var appsChanged: (() -> Void)?
    var didWake: (() -> Void)?
    func runningBundleIDs() -> Set<String> { running }
    func startObserving(appsChanged: @escaping () -> Void, didWake: @escaping () -> Void) {
        self.appsChanged = appsChanged
        self.didWake = didWake
    }
    func stopObserving() {
        appsChanged = nil
        didWake = nil
    }
    func set(_ apps: Set<String>) {
        running = apps
        appsChanged?()
    }
}

private final class FakeWatchdog: LidWatchdog {
    var armed = false
    var history: [Bool] = []
    func arm() {
        if !armed { history.append(true) }
        armed = true
    }
    func disarm() {
        if armed { history.append(false) }
        armed = false
    }
}

/// Scheduled blocks, fired by hand.
@MainActor
private final class FakeScheduler {
    final class Item: LidCancellable {
        let delay: TimeInterval
        let block: @MainActor () -> Void
        var cancelled = false
        init(delay: TimeInterval, block: @escaping @MainActor () -> Void) {
            self.delay = delay
            self.block = block
        }
        func cancel() { cancelled = true }
    }
    var items: [Item] = []
    var live: [Item] { items.filter { !$0.cancelled } }

    func schedule(_ delay: TimeInterval, _ block: @escaping @MainActor () -> Void) -> LidCancellable {
        let item = Item(delay: delay, block: block)
        items.append(item)
        return item
    }

    /// Fires the live item scheduled with this delay.
    func fire(delay: TimeInterval) {
        guard let item = live.last(where: { abs($0.delay - delay) < 0.5 }) else { return }
        item.cancelled = true
        item.block()
    }
}

/// Background work: inline (every command finishes before the call
/// returns), or held until `runPending` — a command still in flight.
private final class FakeBackground: @unchecked Sendable {
    var inline = true
    var pending: [@Sendable () -> Void] = []
    func run(_ work: @escaping @Sendable () -> Void) {
        if inline { work() } else { pending.append(work) }
    }
    func runPending() {
        let work = pending
        pending = []
        work.forEach { $0() }
    }
}

@MainActor
private final class Rig {
    let mac = FakeMac()
    let power = FakePower()
    let workspace = FakeWorkspace()
    let scheduler = FakeScheduler()
    let watchdog = FakeWatchdog()
    let background = FakeBackground()
    let suite = "NotchHubTests.lidController.\(UUID().uuidString)"
    let defaults: UserDefaults
    var now = Date(timeIntervalSince1970: 1_760_300_000)
    var changes = 0
    lazy var controller: LidAwakeController = {
        let background = self.background
        let controller = LidAwakeController(
            runner: FakeRunner(mac: mac), power: power, workspace: workspace, system: FakeLid(mac: mac),
            defaults: defaults, userName: "arnav", clock: { [unowned self] in self.now },
            schedule: { [unowned self] delay, block in self.scheduler.schedule(delay, block) },
            background: { background.run($0) },
            holdsActivity: false,
            watchdog: watchdog,
            readbackDelay: 0,
            quitWait: 0.05
        )
        controller.onChange = { [unowned self] in self.changes += 1 }
        return controller
    }()

    init(settings: LidAwakeSettings = LidAwakeSettings(), owns: Bool = false, sleepDisabled: Bool = false, helper: Bool = false) {
        defaults = UserDefaults(suiteName: suite)!
        mac.defaults = defaults
        settings.save(to: defaults)
        LidAwakeRecord(ownsSleepDisabled: owns, since: owns ? now : nil).save(to: defaults)
        mac.sleepDisabled = sleepDisabled
        mac.helperFile = helper
    }

    deinit { UserDefaults().removePersistentDomain(forName: suite) }

    var savedSettings: LidAwakeSettings { LidAwakeSettings.load(from: defaults) }
    var savedRecord: LidAwakeRecord { LidAwakeRecord.load(from: defaults) }
}

@MainActor
@Suite("Lid awake: the controller", .serialized)
struct LidAwakeControllerTests {

    @Test("launch after a crash: NotchHub's SleepDisabled 1 goes back through the helper, the record is cleared, and a closed lid is put to sleep")
    func crashReconcile() {
        let rig = Rig(owns: true, sleepDisabled: true, helper: true)
        rig.mac.lidClosed = true
        rig.controller.start()
        #expect(rig.mac.calls == ["sudo -n pmset 0"])
        #expect(!rig.mac.sleepDisabled && rig.savedRecord == LidAwakeRecord())
        #expect(rig.controller.model.status == .normal)
        // Twenty seconds on, the lid still closed and no external display: sleep.
        rig.scheduler.fire(delay: LidAwakeController.nudgeDelay)
        #expect(rig.mac.sleepNowCount == 1)
    }

    @Test("the nudge never sleeps a Mac with an external display, or an open lid")
    func nudgeGuards() {
        let rig = Rig(owns: true, sleepDisabled: true, helper: true)
        rig.mac.lidClosed = true
        rig.mac.externalDisplay = true
        rig.controller.start()
        rig.scheduler.fire(delay: LidAwakeController.nudgeDelay)
        #expect(rig.mac.sleepNowCount == 0)

        let open = Rig(owns: true, sleepDisabled: true, helper: true)
        open.controller.start()
        open.scheduler.fire(delay: LidAwakeController.nudgeDelay)
        #expect(open.mac.sleepNowCount == 0)
    }

    @Test("launch with a SleepDisabled 1 NotchHub did not set: nothing runs, the page says so")
    func outside() {
        let rig = Rig(sleepDisabled: true)
        rig.controller.start()
        #expect(rig.mac.calls.isEmpty && rig.mac.sleepDisabled)
        #expect(rig.controller.model.status == .outside)
    }

    @Test("turning it on the first time: one dialog installs the rule (no pmset in it), then sleep goes off through the rule — the record saved before that")
    func firstEnable() {
        let rig = Rig()
        rig.controller.start()
        rig.controller.handle(.setEnabled(true))
        #expect(rig.mac.calls.count == 2)
        let install = rig.mac.calls[0]
        #expect(install.hasPrefix("admin: set -e; umask 077;") && !install.contains("; /usr/bin/pmset"))
        #expect(rig.mac.calls[1] == "sudo -n pmset 1")
        #expect(rig.mac.recordAtCall == [false, true])
        #expect(rig.mac.sleepDisabled && rig.mac.helperFile)
        #expect(rig.savedSettings.enabled && rig.savedRecord.ownsSleepDisabled)
        #expect(rig.controller.model.status == .awake && rig.controller.model.isAwake)
        #expect(rig.watchdog.armed)
        #expect(rig.changes > 0)
    }

    @Test("the rule installed but sudo refuses it: sleep is never turned off — not even through the dialog — and the switch goes back off")
    func firstEnableRefused() {
        let rig = Rig()
        rig.mac.sudoReadsDropIns = false
        rig.controller.start()
        rig.controller.handle(.setEnabled(true))
        #expect(rig.mac.calls.count == 2 && rig.mac.calls[0].hasPrefix("admin: set -e") && rig.mac.calls[1] == "sudo -n pmset 1")
        #expect(!rig.mac.sleepDisabled && rig.mac.helperFile)
        #expect(!rig.savedSettings.enabled && rig.savedRecord == LidAwakeRecord() && !rig.watchdog.armed)
        let model = rig.controller.model
        #expect(model.status == .normal && model.helperLabel == "Not working" && model.isEnabled(.installHelper))
        #expect(model.detail == "That didn't work: sudo: a password is required")
    }

    @Test("cancelling the first dialog: nothing changes, the switch is off again")
    func firstEnableCancelled() {
        let rig = Rig()
        rig.mac.adminAnswer = .cancelled
        rig.controller.start()
        rig.controller.handle(.setEnabled(true))
        #expect(!rig.mac.sleepDisabled && !rig.mac.helperFile)
        #expect(!rig.savedSettings.enabled && rig.savedRecord == LidAwakeRecord())
        #expect(rig.controller.model.status == .normal && rig.controller.model.note == .cancelled)
        #expect(!rig.watchdog.armed)
    }

    @Test("with the helper: unplugging puts sleep back without a prompt, plugging in turns it off again; the dead-man's switch follows")
    func powerGuard() {
        let rig = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        rig.controller.start()
        // Launch checks the helper by re-asserting the 1 NotchHub set.
        #expect(rig.mac.calls == ["sudo -n pmset 1"] && rig.controller.model.status == .awake)
        #expect(rig.watchdog.armed)
        rig.power.set(PowerSnapshot(onAC: false, batteryPercent: 90))
        #expect(rig.mac.calls == ["sudo -n pmset 1", "sudo -n pmset 0"] && !rig.mac.sleepDisabled)
        #expect(rig.controller.model.headline == "Paused: on battery")
        #expect(rig.scheduler.live.contains { $0.delay == LidAwakeController.nudgeDelay })
        #expect(!rig.watchdog.armed)
        rig.power.set(PowerSnapshot(onAC: true, batteryPercent: 90))
        #expect(rig.mac.calls.last == "sudo -n pmset 1" && rig.mac.sleepDisabled)
        #expect(rig.controller.model.status == .awake && rig.watchdog.armed)
        #expect(rig.watchdog.history == [true, false, true])
    }

    @Test("the chosen apps: the last one quitting lets the Mac sleep, one opening keeps it working")
    func appsGuard() {
        let settings = LidAwakeSettings(enabled: true, onlyWhileApps: true, apps: ["com.example.agent"])
        let rig = Rig(settings: settings, owns: true, sleepDisabled: true, helper: true)
        rig.workspace.running = ["com.example.agent"]
        rig.controller.start()
        #expect(rig.controller.model.openApps == ["com.example.agent"])
        rig.workspace.set(["com.apple.finder"])
        #expect(!rig.mac.sleepDisabled && rig.controller.model.status == .held(.appsClosed))
        rig.workspace.set(["com.apple.finder", "com.example.agent"])
        #expect(rig.mac.sleepDisabled && rig.controller.model.status == .awake)
    }

    @Test("auto-off: a timer at the deadline turns the switch off and puts sleep back")
    func autoOff() {
        let rig = Rig(settings: LidAwakeSettings(enabled: true, autoOffHours: 1, clockStart: Date(timeIntervalSince1970: 1_760_300_000)),
                      owns: true, sleepDisabled: true, helper: true)
        rig.controller.start()
        let timer = rig.scheduler.live.first { $0.delay > 3000 }
        #expect(timer.map { abs($0.delay - 3600.25) < 0.01 } == true)
        rig.now = rig.now.addingTimeInterval(3601)
        rig.scheduler.fire(delay: 3600.25)
        #expect(!rig.mac.sleepDisabled && !rig.savedSettings.enabled)
        #expect(rig.controller.model.detail.hasPrefix("Turned itself off after 1 h"))
    }

    @Test("a woken Mac re-reads pmset: sleep put back by hand clears NotchHub's record")
    func wakeRefresh() {
        let rig = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        rig.controller.start()
        rig.mac.sleepDisabled = false       // someone ran pmset -a disablesleep 0
        rig.mac.helperWorks = false         // …and the rule no longer works
        rig.workspace.didWake?()
        // The guards still want it awake: sudo -n is tried, refused, and it
        // waits for the user rather than prompting on its own.
        #expect(rig.mac.calls == ["sudo -n pmset 1", "sudo -n pmset 1"])
        #expect(rig.controller.model.status == .needsYou && rig.controller.model.helperLabel == "Not working")
        #expect(!rig.mac.calls.contains { $0.hasPrefix("admin:") })
        // Resume: one dialog reinstalls the helper, then sleep goes off through it.
        rig.controller.handle(.resume)
        #expect(rig.mac.calls.suffix(2).first?.hasPrefix("admin: set -e") == true && rig.mac.calls.last == "sudo -n pmset 1")
        #expect(rig.controller.model.status == .awake)
    }

    @Test("kept awake with a refused helper: normal sleep goes back — one dialog with the lid open, retried silently every minute")
    func refusedHelperRestores() {
        let rig = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        rig.mac.helperWorks = false
        rig.controller.start()
        #expect(rig.mac.calls == ["sudo -n pmset 1", "sudo -n pmset 0", "admin: /usr/bin/pmset -a disablesleep 0"])
        #expect(!rig.mac.sleepDisabled && rig.savedRecord == LidAwakeRecord())
        #expect(rig.controller.model.status == .needsYou)
    }

    @Test("a restore that fails behind a closed lid: no dialog at all, a retry every minute — and the dialog once the lid is open")
    func restoreBehindClosedLid() {
        let rig = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        rig.controller.start()
        rig.mac.helperWorks = false
        rig.mac.lidClosed = true
        rig.power.set(PowerSnapshot(onAC: false, batteryPercent: 60))
        #expect(rig.mac.calls == ["sudo -n pmset 1", "sudo -n pmset 0"])
        #expect(rig.mac.sleepDisabled && rig.controller.model.status == .stillOff)
        #expect(rig.scheduler.live.contains { $0.delay == LidAwakeController.restoreRetryInterval })
        // A minute on, still closed: the helper again, still no dialog.
        rig.scheduler.fire(delay: LidAwakeController.restoreRetryInterval)
        #expect(rig.mac.calls.suffix(1) == ["sudo -n pmset 0"] && rig.mac.calls.count == 3)
        // The lid opens: the next try may show the dialog — once.
        rig.mac.lidClosed = false
        rig.scheduler.fire(delay: LidAwakeController.restoreRetryInterval)
        #expect(rig.mac.calls.suffix(2) == ["sudo -n pmset 0", "admin: /usr/bin/pmset -a disablesleep 0"])
        #expect(!rig.mac.sleepDisabled && rig.savedRecord == LidAwakeRecord())
        // Done: no more retries.
        #expect(!rig.scheduler.live.contains { $0.delay == LidAwakeController.restoreRetryInterval })
    }

    @Test("a dialog shown and not answered (timed out) is not shown again on its own; the helper keeps being tried")
    func restorePromptOnce() {
        let rig = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        rig.controller.start()
        rig.mac.helperWorks = false
        rig.mac.adminAnswer = .failed("the password prompt timed out")
        rig.power.set(PowerSnapshot(onAC: false, batteryPercent: 60))
        #expect(rig.mac.calls.filter { $0.hasPrefix("admin:") }.count == 1)
        rig.power.set(PowerSnapshot(onAC: false, batteryPercent: 59))
        rig.scheduler.fire(delay: LidAwakeController.restoreRetryInterval)
        #expect(rig.mac.calls.filter { $0.hasPrefix("admin:") }.count == 1)
        #expect(rig.mac.calls.filter { $0 == "sudo -n pmset 0" }.count == 3)
        // The helper works again: back to normal.
        rig.mac.helperWorks = true
        rig.scheduler.fire(delay: LidAwakeController.restoreRetryInterval)
        #expect(!rig.mac.sleepDisabled && rig.controller.model.status == .held(.onBattery))
    }

    @Test("quit: normal sleep back synchronously through the helper — never a dialog — unless kept by choice; the dead-man's switch stands down")
    func quit() {
        let rig = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        rig.controller.start()
        rig.controller.prepareForQuit()
        #expect(rig.mac.calls == ["sudo -n pmset 1", "sudo -n pmset 0"] && !rig.mac.sleepDisabled && rig.savedRecord == LidAwakeRecord())
        #expect(!rig.controller.isRunning && !rig.watchdog.armed)

        let keep = Rig(settings: LidAwakeSettings(enabled: true, keepAfterQuit: true), owns: true, sleepDisabled: true, helper: true)
        keep.controller.start()
        #expect(!keep.watchdog.armed)
        keep.controller.prepareForQuit()
        #expect(keep.mac.calls == ["sudo -n pmset 1"] && keep.mac.sleepDisabled && keep.savedRecord.ownsSleepDisabled)

        // The helper failing at quit: no dialog; the record stays for the next launch.
        let broken = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        broken.controller.start()
        broken.mac.helperWorks = false
        broken.controller.prepareForQuit()
        #expect(broken.mac.calls == ["sudo -n pmset 1", "sudo -n pmset 0"] && broken.mac.sleepDisabled)
        #expect(broken.savedRecord.ownsSleepDisabled)

        // Never started (an inspection launch): quitting touches nothing.
        let idle = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        idle.controller.prepareForQuit()
        #expect(idle.mac.calls.isEmpty)
    }

    @Test("quit with a turn-on in flight: it is stopped and waited for, pmset read afresh (not the cached 0), sleep put back; its answer is ignored")
    func quitWhileBusy() {
        let rig = Rig(settings: LidAwakeSettings(enabled: true), helper: true)
        rig.power.current = PowerSnapshot(onAC: false, batteryPercent: 80)
        rig.controller.start()              // on battery: the launch probe ran inline
        rig.background.inline = false
        rig.power.set(PowerSnapshot(onAC: true, batteryPercent: 80))
        #expect(rig.controller.engine.busy && rig.savedRecord.ownsSleepDisabled && rig.controller.engine.observed == false)
        // Stopping it lets the in-flight work finish (its sudo terminated)…
        let before = rig.changes
        rig.mac.onCancel = { [background = rig.background] in background.runPending() }
        // …though say it had landed just before: SleepDisabled is 1 by now.
        rig.mac.sleepDisabled = true
        rig.controller.prepareForQuit()
        #expect(rig.mac.calls.suffix(3) == ["cancel", "sudo -n pmset 1", "sudo -n pmset 0"])
        #expect(!rig.mac.sleepDisabled && rig.savedRecord == LidAwakeRecord())
        // Its answer reached a NotchHub that had quit: nothing changed.
        #expect(rig.changes == before && !rig.watchdog.armed)
    }

    @Test("quit waits only so long for a stuck command, then puts sleep back anyway; a dialog never opens after")
    func quitWhileStuck() {
        let rig = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        rig.controller.start()
        rig.background.inline = false
        rig.mac.helperWorks = false
        rig.power.set(PowerSnapshot(onAC: false, batteryPercent: 50))   // a restore, stuck in flight
        rig.mac.helperWorks = true
        rig.controller.prepareForQuit()
        #expect(rig.mac.calls.suffix(2) == ["cancel", "sudo -n pmset 0"])
        #expect(!rig.mac.sleepDisabled && rig.savedRecord == LidAwakeRecord())
        // The stuck work finally runs: its helper fails, and its dialog is refused.
        rig.mac.helperWorks = false
        rig.background.runPending()
        #expect(rig.mac.calls.last == "admin: /usr/bin/pmset -a disablesleep 0")
        #expect(!rig.mac.sleepDisabled)
    }

    @Test("Remove: one dialog puts sleep back and deletes the rule; the switch is off")
    func removeHelper() {
        let rig = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        rig.controller.start()
        rig.controller.handle(.removeHelper)
        #expect(rig.mac.calls.last == "admin: /usr/bin/pmset -a disablesleep 0; /bin/rm -f /private/etc/sudoers.d/notchhub-lid")
        #expect(!rig.mac.helperFile && !rig.mac.sleepDisabled && !rig.savedSettings.enabled)
        #expect(rig.controller.model.helperLabel == "Not set up" && !rig.watchdog.armed)
    }

    @Test("a sub-setting never opens a password dialog to keep the Mac awake")
    func settingsNeverPrompt() {
        let settings = LidAwakeSettings(enabled: true, onlyWhileApps: true, apps: ["com.example.agent"])
        let rig = Rig(settings: settings)
        rig.workspace.running = ["com.example.agent"]
        rig.controller.start()
        #expect(rig.controller.model.status == .needsYou)
        rig.controller.handle(.keepAfterQuit(true))
        rig.controller.handle(.addApp(bundleID: "com.example.chat"))
        rig.controller.handle(.onlyOnPower(false))
        #expect(rig.mac.calls.isEmpty && rig.controller.model.status == .needsYou)
    }

    @Test("before start nothing is touched, and taps are ignored")
    func notStarted() {
        let rig = Rig(owns: true, sleepDisabled: true, helper: true)
        rig.controller.handle(.setEnabled(true))
        rig.power.set(PowerSnapshot(onAC: false, batteryPercent: 5))
        #expect(rig.mac.calls.isEmpty && rig.controller.model.status == .notManaged && !rig.watchdog.armed)
    }

    @Test("settings persist; the page hears of changes only when what it shows changes")
    func settingsAndChanges() {
        let rig = Rig(helper: true)
        rig.controller.start()
        let before = rig.changes
        rig.controller.handle(.onlyOnPower(false))
        rig.controller.handle(.batteryFloor(33))
        rig.controller.handle(.addApp(bundleID: "com.example.agent"))
        rig.controller.handle(.autoOff(hours: 4))
        rig.controller.handle(.keepAfterQuit(true))
        let saved = rig.savedSettings
        #expect(!saved.onlyOnPower && saved.batteryFloor == 35 && saved.apps == ["com.example.agent"])
        #expect(saved.autoOffHours == 4 && saved.keepAfterQuit)
        #expect(rig.changes == before + 5)
        // A battery reading that changes nothing on the page is not news.
        rig.power.set(PowerSnapshot(onAC: true, batteryPercent: 81))
        #expect(rig.changes == before + 5)
        #expect(rig.mac.calls.isEmpty)
    }

    @Test("the dashboard's lid chip: a click is the Settings switch — on (lit, through the same first-time setup), paused (the dot), off — and every change is heard, so the open dashboard redraws")
    func dashboardChip() {
        let rig = Rig()
        rig.controller.start()
        var chip: DashboardLidChip { DashboardLidChip(rig.controller.model) }
        /// What the dashboard does with `.lidAwake`: the chip's click through
        /// the page's own entry point.
        func click() {
            if let intent = DashboardLidChip.click(rig.controller.model) { rig.controller.handle(intent) }
        }
        #expect(chip == .off)

        // The first time: the same one dialog installs the helper, then sleep
        // goes off through it — exactly as the switch in Settings.
        var heard = rig.changes
        click()
        #expect(rig.mac.calls.count == 2 && rig.mac.calls[0].hasPrefix("admin: set -e") && rig.mac.calls[1] == "sudo -n pmset 1")
        #expect(rig.savedSettings.enabled && rig.mac.sleepDisabled && rig.controller.engine.isKeepingAwake)
        #expect(chip == .awake && rig.changes > heard)

        // Unplugged: the guard lets the Mac sleep; the switch stays on.
        heard = rig.changes
        rig.power.set(PowerSnapshot(onAC: false, batteryPercent: 90))
        #expect(!rig.mac.sleepDisabled && rig.savedSettings.enabled && chip == .waiting && rig.changes > heard)

        // A click while paused turns the switch off, as the page's would.
        click()
        #expect(!rig.savedSettings.enabled && !rig.mac.sleepDisabled && chip == .off)

        // Plugged in and clicked with the command still running: the dot at
        // once, a second click does nothing, and the light when it lands.
        rig.power.set(PowerSnapshot(onAC: true, batteryPercent: 90))
        rig.background.inline = false
        click()
        #expect(rig.controller.model.status == .switching(.on) && chip == .waiting)
        let calls = rig.mac.calls
        click()
        #expect(rig.savedSettings.enabled && DashboardLidChip.click(rig.controller.model) == nil)
        rig.background.runPending()
        #expect(rig.mac.calls == calls + ["sudo -n pmset 1"] && chip == .awake)
    }

    @Test("the dashboard's lid chip never looks idle while a closed lid won't sleep the Mac: switched off with the dialog cancelled, or sleep turned off outside NotchHub — the dot")
    func dashboardChipSleepStillOff() {
        // Kept awake, then the helper stops working: the chip's click turns
        // the switch off, the helper is refused, and the one dialog to put
        // sleep back is cancelled — the switch is off, sleep is not.
        let rig = Rig(settings: LidAwakeSettings(enabled: true), owns: true, sleepDisabled: true, helper: true)
        rig.controller.start()
        var chip: DashboardLidChip { DashboardLidChip(rig.controller.model) }
        #expect(chip == .awake)
        rig.mac.helperWorks = false
        rig.mac.adminAnswer = .cancelled
        let intent = DashboardLidChip.click(rig.controller.model)
        #expect(intent == .setEnabled(false))
        if let intent { rig.controller.handle(intent) }
        #expect(rig.mac.calls.suffix(2) == ["sudo -n pmset 0", "admin: /usr/bin/pmset -a disablesleep 0"])
        #expect(!rig.savedSettings.enabled && rig.mac.sleepDisabled && rig.controller.engine.isKeepingAwake)
        #expect(rig.controller.model.status == .stillOff && chip == .waiting)
        // The helper works again and the retry puts sleep back: plain.
        rig.mac.helperWorks = true
        rig.scheduler.fire(delay: LidAwakeController.restoreRetryInterval)
        #expect(!rig.mac.sleepDisabled && rig.controller.model.status == .normal && chip == .off)

        // SleepDisabled 1 that NotchHub did not set, the switch off: the dot.
        let outside = Rig(sleepDisabled: true)
        outside.controller.start()
        #expect(outside.controller.model.status == .outside && DashboardLidChip(outside.controller.model) == .waiting)
        #expect(outside.mac.calls.isEmpty)
    }
}

/// An NSWorkspace whose running list is set by hand, with KVO as the real one.
private final class FakeNSWorkspace: NSWorkspace {
    var apps: [NSRunningApplication] = []
    override var runningApplications: [NSRunningApplication] { apps }
    func setApps(_ new: [NSRunningApplication]) {
        willChangeValue(forKey: "runningApplications")
        apps = new
        didChangeValue(forKey: "runningApplications")
    }
}

@MainActor
@Suite("Lid awake: the system workspace", .serialized)
struct LidAwakeWorkspaceTests {

    @Test("an app that posts no launch / quit notification (menu-bar, agent) is still heard, through the running list's KVO")
    func kvoHearsAgentApps() {
        let fake = FakeNSWorkspace()
        let workspace = SystemWorkspace(workspace: fake)
        var heard = 0
        workspace.startObserving(appsChanged: { heard += 1 }, didWake: {})
        fake.setApps([NSRunningApplication.current])
        #expect(heard == 1)
        fake.setApps([])
        #expect(heard == 2)
        workspace.stopObserving()
        fake.setApps([NSRunningApplication.current])
        #expect(heard == 2)
    }
}

@Suite("Lid awake: reading the system")
struct LidAwakeSystemReadTests {

    /// Runs blocking work (a subprocess, a semaphore) on a global queue, so
    /// it never holds one of the cooperative threads other suites share.
    private func offPool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: work()) }
        }
    }

    @Test("power snapshot from IOKit's dictionaries")
    func powerSnapshot() {
        let battery: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 57, kIOPSMaxCapacityKey: 100]
        #expect(IOKitPowerSource.snapshot(providing: kIOPMACPowerKey, descriptions: [battery]) == PowerSnapshot(onAC: true, batteryPercent: 57))
        #expect(IOKitPowerSource.snapshot(providing: kIOPMBatteryPowerKey, descriptions: [battery]) == PowerSnapshot(onAC: false, batteryPercent: 57))
        #expect(IOKitPowerSource.snapshot(providing: kIOPMUPSPowerKey, descriptions: []) == PowerSnapshot(onAC: true, batteryPercent: nil))
        let scaled: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 2500, kIOPSMaxCapacityKey: 5000]
        #expect(IOKitPowerSource.snapshot(providing: kIOPMBatteryPowerKey, descriptions: [scaled])?.batteryPercent == 50)
        let ups: [String: Any] = [kIOPSTypeKey: "UPS", kIOPSCurrentCapacityKey: 10]
        #expect(IOKitPowerSource.snapshot(providing: kIOPMACPowerKey, descriptions: [ups])?.batteryPercent == nil)
        #expect(IOKitPowerSource.snapshot(providing: nil, descriptions: [battery]) == nil)
    }

    @Test("a tool's status, output and error; a hung one is stopped at its timeout")
    func commandLineTool() async {
        let result = await offPool { CommandLineTool.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], timeout: 10) }
        #expect(result.status == 3 && result.output == "out\n" && result.error == "err\n" && !result.timedOut)
        let hung = await offPool { CommandLineTool.run("/bin/sleep", ["10"], timeout: 0.3) }
        #expect(hung.timedOut && hung.status == -1)
        #expect(await offPool { CommandLineTool.run("/nonexistent/tool", [], timeout: 1) }.status == -1)
        #expect(CommandLineTool.shortError("first\nsudo: a password is required\n", fallback: "x") == "sudo: a password is required")
        #expect(CommandLineTool.shortError("  \n", fallback: "fallback") == "fallback")
    }

    @Test("this Mac, read only: pmset -g parses, and IOKit answers")
    func realReads() async {
        // Reading needs no root and changes nothing.
        #expect(await offPool { SystemLid().sleepDisabled() } != nil)
        #expect(IOKitPowerSource().snapshot() != nil)
        _ = SystemLid().lidClosed()
        _ = SystemLid().externalDisplayConnected()
    }
}

@Suite("Lid awake: the dead-man's switch process", .serialized)
struct ProcessWatchdogTests {

    /// A process to watch, ending on its own.
    private func watched(_ seconds: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        try process.run()
        return process
    }

    private func waitFor(_ path: String, seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return FileManager.default.fileExists(atPath: path)
    }

    // A harmless stand-in for the restore: these never run sudo or pmset.
    private func marker() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("lid-dms-\(UUID().uuidString)").path
    }

    @Test("armed: when the watched process is gone, the restore runs")
    func fires() async throws {
        let path = marker()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let target = try watched("0.3")
        let watchdog = ProcessWatchdog(pid: target.processIdentifier, processName: "nh-no-such-process",
                                       restore: "/usr/bin/touch '\(path)'", interval: 0.1)
        watchdog.arm()
        #expect(watchdog.isArmed)
        #expect(await waitFor(path, seconds: 5))
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(!watchdog.isArmed)
    }

    @Test("disarmed before then: nothing runs")
    func disarmed() async throws {
        let path = marker()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let target = try watched("0.4")
        let watchdog = ProcessWatchdog(pid: target.processIdentifier, processName: "nh-no-such-process",
                                       restore: "/usr/bin/touch '\(path)'", interval: 0.1)
        watchdog.arm()
        watchdog.disarm()
        #expect(!watchdog.isArmed)
        #expect(!(await waitFor(path, seconds: 1.5)))
    }
}
