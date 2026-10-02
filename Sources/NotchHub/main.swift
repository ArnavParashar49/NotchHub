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

    // --- NEO's listening pulse ---
    // Each time NEO starts to listen a glow pulses ONCE behind the pet —
    // 1.4 s, dark to dark — and then nothing shows for the rest of that
    // stretch. It never takes any room.
    let heard = Date(timeIntervalSinceReferenceDate: 0)
    var listening = NeoListeningIndicator()
    check(listening.mark(for: .idle, at: heard) == nil, "no listening mark while NEO is not listening")
    listening.update(listening: true, at: heard)
    check(NeoListeningIndicator.pulseDuration == 1.4 && listening.nextWake(at: heard) == heard.addingTimeInterval(1.4),
          "listening: one pulse of 1.4 s, and the model says when it ends")
    check(listening.mark(for: .idle, at: heard.addingTimeInterval(0.45)) == NeoListeningMark(pulseStart: heard)
            && listening.mark(for: .interactive, at: heard.addingTimeInterval(0.45)) == NeoListeningMark(pulseStart: heard),
          "listening: the glow shows during the pulse — on the idle dock and in a fixed strip alike")
    check(listening.mark(for: .idle, at: heard.addingTimeInterval(1.4)) == nil && listening.mark(for: .idle, at: heard.addingTimeInterval(3)) == nil
            && listening.nextWake(at: heard.addingTimeInterval(1.4)) == nil,
          "listening: nothing once the pulse is over, however long NEO listens")
    listening.update(listening: true, at: heard.addingTimeInterval(3))
    check(listening.mark(for: .idle, at: heard.addingTimeInterval(3.1)) == nil, "still listening: the same stretch never pulses twice")
    check(NeoListeningLayout.pulse(at: 0) == 0 && abs(NeoListeningLayout.pulse(at: 0.45) - 1) < 1e-9 && NeoListeningLayout.pulse(at: 1.4) == 0
            && abs(NeoListeningLayout.glowOpacity(pulse: 1) - 0.8) < 1e-9 && abs(NeoListeningLayout.glowScale(pulse: 1) - 1.06) < 1e-9,
          "the pulse: dark at 0, its peak (opacity 0.8, scale 1.06) at 0.45 s, dark again at 1.4 s")
    check(NeoListeningLayout.glowScale(pulse: 1, reduceMotion: true) == 1 && NeoListeningLayout.glowScale(pulse: 0, reduceMotion: true) == 1,
          "Reduce Motion: the glow fades in and out at a fixed scale")
    check(NeoListeningLayout.glowDiameter(petSize: PetLayout.artSize) * NeoListeningLayout.pulseScaleRange.upperBound <= 32,
          "the glow (the fox + 6 pt) stays inside the 32-pt notch strip at the peak of the pulse")
    var dockedContent = IslandContentSize.default
    dockedContent.petDock = .home
    let selftestGeometry = NotchGeometry.make(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0))
    check(selftestGeometry.frame(for: .idle, content: dockedContent) == selftestGeometry.compactBar(lead: 0, trail: PetLayout.idleDock),
          "listening takes no room: the idle dock is the pet's dock and nothing more")
    listening.update(listening: false, at: heard.addingTimeInterval(4))
    listening.update(listening: true, at: heard.addingTimeInterval(5))
    check(listening.mark(for: .idle, at: heard.addingTimeInterval(5.45)) == NeoListeningMark(pulseStart: heard.addingTimeInterval(5)),
          "a new stretch of listening pulses again")
    listening.update(listening: false, at: heard.addingTimeInterval(5.5))
    check(listening.mark(for: .idle, at: heard.addingTimeInterval(5.5)) == nil, "the mark is gone the moment NEO stops listening, mid-pulse or not")

    // --- NEO's Allow / Cancel under the notch ---
    // A staged confirmation drops two buttons under the notch, over whatever
    // the island shows (but never doubled with NEO's own chat); Allow counts
    // after 0.6 s; answered or over, the island is what it was.
    let asked = Date(timeIntervalSinceReferenceDate: 100)
    let card = NeoConfirmCard(actionID: "trash:4d15", tool: "trash", summary: "move report.pdf to the Trash", detail: "/Users/me/report.pdf")
    var confirm = NeoConfirmModel()
    check(!confirm.receive(.state(.confirming), at: asked) && !confirm.isShowing, "confirm: NEO's state alone shows no buttons")
    check(confirm.receive(.confirm(card), at: asked) && confirm.state(over: .idle) == .neoConfirm && confirm.state(over: .expanded) == .neoConfirm
            && confirm.state(over: .camera) == .neoConfirm && confirm.state(over: .neoPanel) == .neoPanel,
          "confirm: a staged confirmation shows Allow / Cancel over everything but NEO's own chat")
    check(confirm.answer(.allow, at: asked.addingTimeInterval(0.3)) == nil && confirm.isShowing, "confirm: Allow within 0.6 s of the buttons appearing does nothing")
    check(NeoConfirmKey.choice(forKeyCode: 36) == .allow && NeoConfirmKey.choice(forKeyCode: 53) == .cancel && NeoConfirmKey.choice(forKeyCode: 36, isRepeat: true) == nil,
          "confirm: Return allows, Esc cancels, a key held from before does neither")
    let allowed = confirm.answer(.allow, at: asked.addingTimeInterval(0.7))
    check(allowed?.command == #"{"cmd":"confirm","yes":true,"action_id":"trash:4d15"}"# && confirm.state(over: .expanded) == .expanded,
          "confirm: Allow sends the page's own command, and the island is what it was")
    confirm.receive(.confirm(card), at: asked.addingTimeInterval(2))
    check(confirm.receive(.confirmDone(card.actionID), at: asked.addingTimeInterval(3)) && !confirm.isShowing, "confirm: confirm_done (answered elsewhere, expired) clears the buttons")
    confirm.chat(open: true, at: asked.addingTimeInterval(4))
    confirm.receive(.confirm(card), at: asked.addingTimeInterval(5))
    check(!confirm.isShowing && confirm.chat(open: false, at: asked.addingTimeInterval(6)) && confirm.isShowing, "confirm: not doubled with the chat panel; up when it closes")
    let confirmFrame = selftestGeometry.frame(for: .neoConfirm, content: .default)
    let confirmButtons = NeoConfirmLayout.buttons(in: confirmFrame, notchInset: selftestGeometry.notchFrame.height)
    check(confirmFrame.size == CGSize(width: selftestGeometry.notchFrame.width + PetLayout.idleDock * 2, height: selftestGeometry.notchFrame.height + 40)
            && confirmButtons.map(\.choice) == [.allow, .cancel] && confirmButtons.allSatisfy { confirmFrame.contains($0.rect) },
          "confirm: one 40-pt row of two buttons, the notch's width plus the pet's dock each side")
    check(NeoConfirmLayout.choice(at: CGPoint(x: confirmButtons[0].rect.midX, y: confirmButtons[0].rect.midY), in: confirmFrame, notchInset: 32) == .allow
            && NeoConfirmLayout.choice(at: CGPoint(x: confirmButtons[1].rect.midX, y: confirmButtons[1].rect.midY), in: confirmFrame, notchInset: 32) == .cancel
            && NeoConfirmLayout.choice(at: CGPoint(x: confirmFrame.midX, y: confirmButtons[0].rect.midY), in: confirmFrame, notchInset: 32) == nil,
          "confirm: a click lands on the button under it, and on neither between them")

    // --- The first click ---
    // A surface that comes up under a still cursor takes the very next
    // click: the hit region is its final frame at once, the window stops
    // ignoring the mouse without a mouse-move, and the views accept the
    // first click in a window that is not key.
    let region = IslandHitRegion(islandFrame: confirmFrame, idleNotchFrame: selftestGeometry.notchFrame, isIdle: false)
    let onAllow = CGPoint(x: confirmButtons[0].rect.midX, y: confirmButtons[0].rect.midY)
    check(region.catchesMouse(at: onAllow) && !region.windowIgnoresMouse(cursorAt: onAllow, interactive: false),
          "first click: the hit region is the surface's final frame the moment it is presented")
    let firstClick: (window: Bool, container: Bool, hosting: Bool, web: Bool) = MainActor.assumeIsolated {
        let window = NotchWindow(geometry: selftestGeometry)
        window.apply(state: .neoConfirm)
        let frame = window.localFrame(for: .neoConfirm)
        let button = NeoConfirmLayout.buttons(in: frame, notchInset: window.notchHeight)[0].rect
        let hosting = IslandHostingView(rootView: IslandRootView(model: IslandModel()))
        return (
            window.takesClick(at: CGPoint(x: button.midX, y: button.midY)),
            window.acceptsFirstClick,
            hosting.acceptsFirstMouse(for: nil),
            NeoWebView(frame: .zero).acceptsFirstMouse(for: nil)
        )
    }
    check(firstClick.window, "first click: the window hit-tests a button the moment the surface is applied, before any mouse-move")
    check(firstClick.container && firstClick.hosting && firstClick.web, "first click: the island's views and NEO's web view accept the first mouse")

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

// --surface-snapshots DIR: every state of the teleprompter, camera and
// dashboard surfaces, with hit targets (headless).
if let index = arguments.firstIndex(of: "--surface-snapshots") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "."
    // An optional third argument names ONE surface to render.
    let filter = index + 2 < arguments.count ? arguments[index + 2] : nil
    exit(MainActor.assumeIsolated { SurfaceSnapshots.render(directory: directory, filter: filter) })
}

// --neo-snapshots DIR: the pet as NEO, in each of NEO's states and island shapes (headless).
if let index = arguments.firstIndex(of: "--neo-snapshots") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "."
    // An optional third argument keeps only the rows whose name contains it
    // (`listening`: NEO's listening pulse in every shape).
    let filter = index + 2 < arguments.count ? arguments[index + 2] : nil
    exit(MainActor.assumeIsolated { NeoSnapshots.render(directory: directory, filter: filter) })
}

// --neo-glow-zoom DIR: the fox and its listening glow, enlarged — NEO idle, the pulse at its peak, the pulse fading (headless).
if let index = arguments.firstIndex(of: "--neo-glow-zoom") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "."
    exit(MainActor.assumeIsolated { NeoSnapshots.renderGlowZoom(directory: directory) })
}

// --neo-confirm-snapshot DIR: NEO's Allow / Cancel under the notch → DIR/notch-confirm.png (headless).
if let index = arguments.firstIndex(of: "--neo-confirm-snapshot") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "."
    exit(MainActor.assumeIsolated { NeoConfirmSnapshots.render(directory: directory) })
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
