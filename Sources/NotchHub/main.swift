import AppKit
import NotchHubCore
import NotchHubSystem

// MARK: - Headless self-test

/// Exercises the queue + spring math without showing any window, then exits.
/// Prints a concise transcript so the logic can be verified in CI / headless.
func runSelfTest() -> Int32 {
    var failures = 0

    func check(_ condition: Bool, _ label: String) {
        let mark = condition ? "PASS" : "FAIL"
        if !condition { failures += 1 }
        print("[\(mark)] \(label)")
    }

    print("NotchHub self-test — activity queue + spring engine")
    print("")

    // --- ActivityQueue ---
    let queue = ActivityQueue()
    check(queue.isEmpty, "queue starts empty")

    let music = Activity.music(title: "Midnight City", artist: "M83")
    let volume = Activity.volume(0.62)
    let lowBat = Activity.lowBattery(percent: 8)
    let timer = Activity.timer(elapsed: 0)

    queue.push(music)
    queue.push(volume)
    queue.push(lowBat)
    queue.push(timer)

    check(queue.current?.kind == .lowBattery, "highest priority (low battery) wins the island")
    check(queue.stackCount == 3, "stack counts the three behind the primary")

    queue.remove(id: lowBat.id)
    check(queue.current?.kind == .timer, "next-highest (timer) takes the island after removal")

    // Auto-dismiss: a short-lived volume event should expire.
    let short = Activity.volume(0.5)
    queue.push(short)
    let future = Date().addingTimeInterval(10)
    let dismissed = queue.tick(now: future)
    check(dismissed.contains(where: { $0.id == short.id }), "expired activity auto-dismisses")
    check(!queue.all.contains(where: { $0.id == short.id }), "dismissed activity leaves the queue")

    // Replaceable kinds: pushing a newer volume replaces the old one.
    queue.removeAll()
    let v1 = Activity.volume(0.3)
    let v2 = Activity.volume(0.7)
    queue.push(v1)
    queue.push(v2)
    check(queue.all.count == 1, "replaceable kind (volume) supersedes, does not stack")
    check(queue.current?.progress == 0.7, "replacement carries the newest value")

    // Transient-return: a volume change surfaces over playing music, then
    // hands the island back once its lifetime elapses.
    queue.removeAll()
    let persistentMusic = queue.push(.music(title: "Midnight City", artist: "M83"))
    queue.focusTemporarily(.volume(0.5))
    check(queue.current?.kind == .volume, "transient (volume) takes the island over persistent music")
    queue.tick(now: Date().addingTimeInterval(5))
    check(queue.current?.id == persistentMusic.id, "after the transient expires, the island returns to music")

    print("")

    // --- IslandStateMachine ---
    let machine = IslandStateMachine()
    check(machine.presentation == .idle, "machine starts idle")
    // Music can expand: it holds controls the compact bar cannot show.
    machine.setActivity(.music(title: "Midnight City", artist: "M83"))
    check(machine.send(.activityStarted) == .compact, "activityStarted moves idle → compact")
    check(machine.send(.hoverEntered) == .expanded, "hoverEntered moves compact → expanded")
    check(machine.send(.clicked) == .interactive, "clicked moves expanded → interactive")
    check(machine.send(.clicked) == .compact, "clicking the dashboard closes it to the compact bar")
    check(machine.send(.hoverEntered) == .expanded, "hovering the bar expands it again")

    // Hover exit is gated so a momentary leave doesn't collapse.
    machine.send(.hoverExited)
    check(machine.presentation == .expanded, "hoverExited does not collapse immediately")
    check(!machine.shouldCollapse(now: Date()), "shouldCollapse is false right after exit")
    let later = Date().addingTimeInterval(machine.hoverCollapseDelay + 0.1)
    check(machine.shouldCollapse(now: later), "shouldCollapse is true after hoverCollapseDelay")
    check(machine.tick(later) == .compact, "tick collapses expanded → compact after the delay")

    // A readout that is complete in the bar never expands.
    let mCompact = IslandStateMachine()
    mCompact.setActivity(.volume(0.5))
    mCompact.send(.activityStarted)
    check(mCompact.send(.hoverEntered) == .compact, "a compact-only readout stays compact on hover")
    check(mCompact.send(.clicked) == .interactive, "a click on a compact-only readout opens the dashboard")

    // The machine never gets stuck: an expired transient collapses to idle.
    let m2 = IslandStateMachine()
    m2.setActivity(Activity(kind: .music, title: "Midnight City", autoDismiss: 1.6))
    m2.send(.activityStarted)
    m2.send(.clicked)
    let t1 = Date().addingTimeInterval(m2.autoCollapseDelay + 0.1)
    check(m2.tick(t1) == .idle, "an expired transient collapses expanded → idle in one motion")

    print("")

    // --- Spring ---
    let spring = Spring.expand
    let start = spring.value(from: 0, to: 100, at: 0)
    check(abs(start) < 1e-9, "spring starts at the origin")

    let mid = spring.value(from: 0, to: 100, at: 0.2)
    check(mid > 0 && mid < 200, "spring is in flight mid-transition")

    let settled = spring.value(from: 0, to: 100, at: 2.0)
    check(abs(settled - 100) < 1.0, "spring converges to the target")

    // No NaN across a sweep.
    var nan = false
    for i in 0...400 {
        let v = spring.value(from: -50, to: 150, at: Double(i) / 240)
        if v.isNaN { nan = true }
    }
    check(!nan, "spring produces no NaN across a sweep")

    // Underdamped expand overshoots slightly, then settles.
    let expand = Spring.expand
    let peak = (0...240).map { expand.value(from: 0, to: 100, at: Double($0) / 240) }.max() ?? 0
    check(peak > 100 && peak < 112, "expand has a whisper of overshoot (\(String(format: "%.1f", peak)))")

    // Retarget carries velocity — no snap.
    var animator = SpringAnimator(from: 0, to: 100, spring: .expand)
    for _ in 0..<30 { animator.step(1.0 / 240) }
    let before = animator.value
    animator.retarget(to: 60, spring: .settle)
    check(abs(animator.value - before) < 0.5, "retarget does not snap the value")

    // --- System layer → activity bridge ---
    // Verifies the separation: neutrally-shaped system events become activities,
    // and lifecycle events that have no surface map to nothing.
    let batteryEvent = SystemEvent(source: .battery, payload: .battery(percent: 82, charging: true, chargingChanged: true))
    let batteryActivity = ActivityBridge.activity(for: batteryEvent)
    check(batteryActivity?.kind == .battery, "battery event bridges to a battery activity")
    check(batteryActivity?.progress == 0.82, "bridge carries the battery level through")

    let volumeEvent = SystemEvent(source: .volume, payload: .volume(level: 0.4))
    check(ActivityBridge.activity(for: volumeEvent)?.kind == .volume, "volume event bridges to a volume activity")

    let playing = SystemEvent(source: .nowPlaying, payload: .nowPlaying(title: "Solo", artist: "Frank Ocean", isPlaying: true, artwork: nil, source: nil))
    let musicActivity = ActivityBridge.activity(for: playing)
    check(musicActivity?.kind == .music, "now-playing event bridges to a music activity")
    check(musicActivity?.subtitle == "Frank Ocean", "bridge preserves the artist")

    check(ActivityBridge.activity(for: SystemEvent(source: .system, payload: .didWake)) == nil,
          "lifecycle events with no surface map to nil")
    check(ActivityBridge.activity(for: SystemEvent(source: .nowPlaying, payload: .nowPlayingStopped)) == nil,
          "playback-stopped maps to nil (handled by the queue)")

    print("")
    print(failures == 0 ? "SELF-TEST PASSED" : "SELF-TEST FAILED (\(failures) failures)")
    return failures == 0 ? 0 : 1
}

// MARK: - Geometry dump

/// Prints the live display + notch geometry so positioning can be verified and
/// the island's exact screen coordinates are known. Headless-safe.
func runGeometryDump() -> Int32 {
    for (index, screen) in NSScreen.screens.enumerated() {
        print("--- screen \(index)\(screen == NSScreen.main ? " (main)" : "") ---")
        print("frame:        \(screen.frame)")
        print("visibleFrame: \(screen.visibleFrame)")
        print("insets:       \(screen.safeAreaInsets)")
        print("auxTopLeft:   \(String(describing: screen.auxiliaryTopLeftArea))")
        print("auxTopRight:  \(String(describing: screen.auxiliaryTopRightArea))")
        print("scale:        \(screen.backingScaleFactor)")
    }
    let g = NotchGeometry.detectMain()
    print("--- derived island geometry ---")
    print("hasNotch:     \(g.hasNotch)")
    print("cornerRadius: \(g.cornerRadius)")
    func dump(_ name: String, _ r: CGRect) {
        let top = NSScreen.main.map { $0.frame.maxY - r.maxY } ?? 0
        print("\(name): appkit=\(r)")
        print("   top-left-origin: x=\(r.minX) y=\(top) w=\(r.width) h=\(r.height)  center=(\(r.midX), \(top + r.height / 2))")
    }
    dump("notch", g.notchFrame)
    dump("compact", g.compactFrame)
    dump("expanded", g.expandedFrame)
    return 0
}

// MARK: - Entry point

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    exit(runSelfTest())
}

if arguments.contains("--geometry") {
    exit(runGeometryDump())
}

// --agent-sessions: print what each session reader finds (any age), to
// verify tracking against real Claude Code / Codex / Foxora data.
if arguments.contains("--agent-sessions") {
    let sessions = AgentSessionProbe.latest()
    if sessions.isEmpty { print("no agent sessions found") }
    for s in sessions {
        let context = s.contextTokens.map { "\(AgentFormat.tokens($0))/\(AgentFormat.tokens(s.contextLimit))" } ?? "-"
        let last = s.lastActivity.map { "\(Int(Date().timeIntervalSince($0)))s ago" } ?? "-"
        print("\(s.tool): model=\(s.model ?? "?") working=\(s.isWorking) tokens=\(AgentFormat.tokens(s.tokens)) turns=\(s.turns) context=\(context) limits=\(s.limits.count) project=\(s.project ?? "-") last=\(last)")
    }
    exit(0)
}

// --meeting-probe: what the Accessibility scan reads from open calls right now.
if arguments.contains("--meeting-probe") {
    print("accessibility trusted: \(MeetingProbe.isTrusted)")
    let results = MeetingProbe.run()
    if results.isEmpty { print("no call apps or Meet windows found") }
    func show(_ value: Bool?) -> String { value.map { "\($0)" } ?? "unknown" }
    for r in results {
        print("\(r.app) [\(r.window)]: inCall=\(show(r.inCall)) muted=\(show(r.isMuted)) cameraOn=\(show(r.isCameraOn)) leaveButton=\(r.hasLeave)")
    }
    exit(0)
}

// --pet-storyboard DIR [SEED]: render the pet's mischief frame by frame (headless).
if let index = arguments.firstIndex(of: "--pet-storyboard") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "."
    let seed = index + 2 < arguments.count ? UInt64(arguments[index + 2]) ?? 1 : 1
    exit(MainActor.assumeIsolated { PetStoryboard.run(directory: directory, seed: seed) })
}

// --pet-panel-snapshots DIR: the real pet panel with its hit targets outlined (headless).
if let index = arguments.firstIndex(of: "--pet-panel-snapshots") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "."
    exit(MainActor.assumeIsolated { PetStoryboard.panelSnapshots(directory: directory) })
}

// --app-snapshots DIR: a browser's hover strip and panel with hit targets (headless).
if let index = arguments.firstIndex(of: "--app-snapshots") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "."
    exit(MainActor.assumeIsolated { PetStoryboard.appSnapshots(directory: directory) })
}

// --pet-snapshots DIR: the real IslandView's pet layer in each dock shape (headless).
if let index = arguments.firstIndex(of: "--pet-snapshots") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "."
    exit(MainActor.assumeIsolated { PetStoryboard.snapshots(directory: directory) })
}

// --demo: show the island on screen with a scripted sequence.
let isDemo = arguments.contains("--demo")

@MainActor
func runApp() {
    let app = NSApplication.shared
    let delegate = NotchHubApp()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

MainActor.assumeIsolated {
    runApp()
}

// If we got here without the app running, something is wrong.
if !isDemo {
    print("NotchHub launched as an accessory app. Use --selftest to verify logic headlessly, or --demo to preview the island.")
}
