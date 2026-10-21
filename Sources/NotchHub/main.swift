import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

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
    check(selftestGeometry.frame(for: .idle, content: dockedContent) == selftestGeometry.dockBar(lead: 0, trail: PetLayout.idleDock),
          "listening takes no room: the idle dock is the pet's dock and nothing more")
    listening.update(listening: false, at: heard.addingTimeInterval(4))
    listening.update(listening: true, at: heard.addingTimeInterval(5))
    check(listening.mark(for: .idle, at: heard.addingTimeInterval(5.45)) == NeoListeningMark(pulseStart: heard.addingTimeInterval(5)),
          "a new stretch of listening pulses again")
    listening.update(listening: false, at: heard.addingTimeInterval(5.5))
    check(listening.mark(for: .idle, at: heard.addingTimeInterval(5.5)) == nil, "the mark is gone the moment NEO stops listening, mid-pulse or not")

    // --- NEO's camera preview ---
    // The picture flips with the Mirror setting, as its boxes do: a frame red
    // on its left half and blue on its right shows blue on the left mirrored.
    let mirrorSides = MainActor.assumeIsolated {
        (plain: selfTestCameraSides(mirrored: false), mirrored: selfTestCameraSides(mirrored: true))
    }
    check(mirrorSides.plain.map { !$0.left && $0.right } ?? false, "NEO camera: unmirrored, the picture is as NEO sent it")
    check(mirrorSides.mirrored.map { $0.left && !$0.right } ?? false, "NEO camera: mirrored, the picture flips with its boxes")

    // --- The compact bar's visualizer ---
    // It widens with a centred bar, but always keeps an inset clear at the
    // notch end; on a short row it is its usual size.
    let musicRow = IslandMetrics.compact(Activity.music(title: "Midnight City", artist: "M83"), petSlot: PetLayout.barSlot)
    check(IslandView.compactVisualizerWidth(side: musicRow.compactTrail, petReserve: PetLayout.barSlot) == IslandMetrics.musicVisualizerWidth,
          "visualizer: its usual width on a short music row")
    for side: CGFloat in [120, 200, 300] {
        let width = IslandView.compactVisualizerWidth(side: side, petReserve: PetLayout.barSlot)
        let notchGap = side - DesignTokens.compactInset - PetLayout.barSlot - width
        check(notchGap == DesignTokens.compactInset, "visualizer: an inset clear of the notch in a \(Int(side))-pt lane")
    }

    // --- NEO's timers on the island ---
    // The soonest of NEO's timers counts down in the compact bar, as NEO's
    // own kind (never the focus timer's); its seconds tick without the bar
    // changing width, a long name is cut so the clock always shows, and with
    // no timer nothing of NEO's is on the island.
    let timerClock = Date(timeIntervalSince1970: 1_760_270_000)
    var neoTimerModel = NeoTimers()
    var neoTimerSurface = NeoTimerSurface()
    let timerQueue = ActivityQueue()
    check(!neoTimerSurface.sync(neoTimerModel, shows: true, in: timerQueue, at: timerClock) && timerQueue.isEmpty,
          "NEO timers: none running, nothing on the island")
    let pastaTimer = NeoTimerInfo(id: "timer:3f2a9c1b7d4e", title: "Pasta", endsAt: timerClock.addingTimeInterval(252))
    let timerChange = neoTimerModel.receive(.neoTimers([pastaTimer]))
    neoTimerSurface.apply(timerChange, timers: neoTimerModel, shows: true, in: timerQueue, at: timerClock)
    check(timerQueue.current?.kind == .neoTimer && timerQueue.current?.compactText == "Pasta 4:12" && timerQueue.current?.priority == 70,
          "NEO timers: the soonest counts down as NEO's own kind, at the timer's priority (\(timerQueue.current?.compactText ?? "none"))")
    let secondWidths = Set(["4:12", "4:11", "4:10", "1:11", "0:00", "8:88"].map {
        IslandMetrics.compact(Activity(kind: .neoTimer, title: "Pasta", subtitle: $0), petSlot: PetLayout.barSlot).compactTrail
    })
    check(secondWidths.count == 1, "NEO timers: the compact bar holds still as the seconds tick (\(secondWidths.sorted()))")
    let tabular = IslandMetrics.textWidth("0:00", monospacedDigits: true)
    check(tabular == IslandMetrics.textWidth("1:11", monospacedDigits: true) && tabular == IslandMetrics.textWidth("8:88", monospacedDigits: true),
          "NEO timers: the clock is measured in tabular digits, as it is drawn")
    let longLine = NeoTimers.countdownLine(
        NeoTimerInfo(id: "timer:a", title: String(repeating: "W", count: 40), endsAt: timerClock.addingTimeInterval(3_852)), at: timerClock)
    let longRow = IslandMetrics.compact(Activity(kind: .neoTimer, title: longLine.name, subtitle: longLine.value), petSlot: PetLayout.barSlot)
    let plainRow = IslandMetrics.compact(Activity(kind: .neoTimer, title: "Pasta", subtitle: "1:04:12"), petSlot: PetLayout.barSlot)
    check(longLine.value == "1:04:12"
            && longRow.compactTrail - plainRow.compactTrail <= IslandMetrics.maxCompactNeoTimerNameWidth - IslandMetrics.textWidth("Pasta"),
          "NEO timers: a long name is cut at a music title's width, so the clock always fits (\(Int(longRow.compactTrail)) pt a side)")

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
    // "Listen for “Neo”" in Settings → NEO: the switch shows what NEO's core
    // said, its caption what that means for the microphone, and a tap is the
    // core's set command — only while there is a core that has the setting.
    let listens = NeoSettingsModel(featureOn: true, connected: true, shell: nil, core: NeoCoreSettings(wakeWord: true))
    let summoned = NeoSettingsModel(featureOn: true, connected: true, shell: NeoShellStatus(app: true, hotkey: "⌥⌘"), core: NeoCoreSettings(wakeWord: false))
    check(listens.listensForNeo && listens.wakeWordCaption == "The microphone stays on to hear “Neo”." && listens.isEnabled(.wakeWord(false)),
          "wake word: on, the microphone stays on to hear “Neo”")
    check(!summoned.listensForNeo && summoned.wakeWordCaption == "Summon with ⌥⌘ — the microphone is on only while NEO listens.",
          "wake word: off, NEO is summoned with its keys and the microphone is on only while it listens")
    check(NeoSettingsIntent.wakeWord(false).setting?.command == #"{"cmd":"set","name":"wake_word","value":false}"#
            && NeoListener.coreSettings(in: #"{"type":"settings","data":{"wake_word":false},"ts":1}"#) == NeoCoreSettings(wakeWord: false),
          "wake word: a tap is the core's set command, and the switch follows the core's settings event")
    check(!NeoSettingsModel(featureOn: true, connected: false, shell: nil, core: NeoCoreSettings(wakeWord: false)).isEnabled(.wakeWord(true))
            && !NeoSettingsModel(featureOn: true, connected: true, shell: nil).isEnabled(.wakeWord(false)),
          "wake word: the switch is dim while NEO isn't running, or its core has no such setting")

    let confirmFrame = selftestGeometry.frame(for: .neoConfirm, content: .default)
    let confirmButtons = NeoConfirmLayout.buttons(in: confirmFrame, notchInset: selftestGeometry.notchFrame.height)
    check(confirmFrame.size == CGSize(width: selftestGeometry.notchFrame.width + PetLayout.idleDock * 2, height: selftestGeometry.notchFrame.height + 40)
            && confirmButtons.map(\.choice) == [.allow, .cancel] && confirmButtons.allSatisfy { confirmFrame.contains($0.rect) },
          "confirm: one 40-pt row of two buttons, the notch's width plus the pet's dock each side")
    check(NeoConfirmLayout.choice(at: CGPoint(x: confirmButtons[0].rect.midX, y: confirmButtons[0].rect.midY), in: confirmFrame, notchInset: 32) == .allow
            && NeoConfirmLayout.choice(at: CGPoint(x: confirmButtons[1].rect.midX, y: confirmButtons[1].rect.midY), in: confirmFrame, notchInset: 32) == .cancel
            && NeoConfirmLayout.choice(at: CGPoint(x: confirmFrame.midX, y: confirmButtons[0].rect.midY), in: confirmFrame, notchInset: 32) == nil,
          "confirm: a click lands on the button under it, and on neither between them")

    // --- Search Screen's card in NEO's panel ---
    let macbook = CGSize(width: 1512, height: 982)
    check(NeoPanelLayout.pageSize(requested: CGSize(width: 372, height: 200), screen: macbook, minimum: NeoPanelLayout.lensMinimum) == CGSize(width: 372, height: 200)
            && NeoPanelLayout.pageSize(requested: CGSize(width: 372, height: 200), screen: macbook) == CGSize(width: 372, height: 300),
          "lens card: 372×200 stays 372×200 while Search Screen's card is open; the chat's minimum stays 300 tall")
    var lensCard = NeoLensCardModel()
    let lensCID = String(repeating: "0f", count: 16)
    check(lensCard.receive(cid: lensCID, open: true, why: "", canShow: true) == .offer(lensCID) && lensCard.due(cid: lensCID) == .open(lensCID)
            && lensCard.receive(cid: lensCID, open: false, why: "continue", canShow: true) == .close(fold: false)
            && { var busy = NeoLensCardModel(); return busy.receive(cid: lensCID, open: true, why: "", canShow: false) == .refuse(lensCID) }(),
          "lens card: offered → shown and opened 240 ms later; Continue in NEO keeps the panel; a busy island refuses it")
    let quiet: (editing: Bool, noKeys: Bool) = MainActor.assumeIsolated {
        let editing: (String, NSEvent.ModifierFlags) -> Selector? = { key, flags in
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0).flatMap(NotchWindow.editingAction(for:))
        }
        return (
            editing("c", .command) == #selector(NSText.copy(_:)) && editing("v", .command) == #selector(NSText.paste(_:))
                && editing("z", [.command, .shift]) == Selector(("redo:")) && editing("c", .control) == nil && editing("q", .command) == nil,
            !NotchWindow(geometry: selftestGeometry).canBecomeKey
        )
    }
    check(quiet.editing, "lens card: with the keys taken quietly, ⌘C ⌘V ⌘X ⌘A ⌘Z ⇧⌘Z reach the page; other shortcuts are left alone")
    let route: (pageFirst: Bool, leftAlone: Bool, notQuiet: Bool) = MainActor.assumeIsolated {
        let copyKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
                                       characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        var order: [String] = []
        let taken = NotchWindow.routeKeyEquivalent(copyKey, quiet: true, page: { order.append("page"); return true },
                                                   send: { order.append(NSStringFromSelector($0)); return true })
        let pageFirst = taken && order == ["page"]
        order = []
        let sent = NotchWindow.routeKeyEquivalent(copyKey, quiet: true, page: { order.append("page"); return false },
                                                  send: { order.append(NSStringFromSelector($0)); return true })
        let leftAlone = sent && order == ["page", "copy:"]
        order = []
        let loud = NotchWindow.routeKeyEquivalent(copyKey, quiet: false, page: { order.append("page"); return false },
                                                  send: { order.append(NSStringFromSelector($0)); return true })
        return (pageFirst, leftAlone, !loud && order == ["page"])
    }
    check(route.pageFirst && route.leftAlone && route.notQuiet,
          "lens card: ⌘C reaches the page first (its own copy of the area's text); only a key it left alone is sent as Copy")
    check(!NeoLensCardModel.canShow(neoOn: true, hasPage: true, panelFree: true, confirmWaiting: true)
            && !NeoLensCardModel.canShow(neoOn: true, hasPage: true, panelFree: false, confirmWaiting: false)
            && NeoLensCardModel.canShow(neoOn: true, hasPage: true, panelFree: true, confirmWaiting: false),
          "lens card: refused while a question waits for an OK or another panel (teleprompter, camera, Settings…) has the island")
    check(quiet.noKeys, "lens card: the island's window takes no keys until a panel needs them (or takes them quietly)")
    let still: Bool = MainActor.assumeIsolated {
        let window = NotchWindow(geometry: selftestGeometry)
        window.releaseQuietKeys() // (no keys of a card's: nothing to give back, nothing ordered)
        return window.animationBehavior == .none && window.quietKeys.phase == .none && !window.isVisible
    }
    check(still, "lens card: the island's window has no AppKit ordering animation — giving the keys back never fades or shrinks the island")
    var foldKeys = NeoQuietKeys()
    foldKeys.take()
    let foldStart = Date(timeIntervalSinceReferenceDate: 0)
    let keysBack = foldKeys.fold(isKey: true, at: foldStart)
    var typedKeys = foldKeys
    check(keysBack == foldStart.addingTimeInterval(DesignTokens.retractFadeDelay) && foldKeys.isReturning && !foldKeys.isTaken
            && foldKeys.due(keysBack!) && foldKeys.phase == .none && typedKeys.typed(),
          "lens card: on a fold the page lets go of the keys at once; they go back once the retract is home (or on the next key pressed)")

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

    // --- Lid closed ---
    // Keep working with the lid closed: the exact helper rule, pmset's
    // SleepDisabled read, a guard, and the crash reconcile. (Nothing here
    // runs pmset or sudo.)
    check(LidAwakeHelperRule(user: "alex")?.content == "alex ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
            && LidAwakeHelperRule(user: "a b") == nil && LidAwakeHelperRule.path == "/private/etc/sudoers.d/notchhub-lid",
          "lid: the helper rule grants exactly pmset -a disablesleep 0 / 1, and a name needing escapes is refused")
    check(LidAwakeCommands.sleepDisabled(inPmsetOutput: "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n") == true
            && LidAwakeCommands.sleepDisabled(inPmsetOutput: "System-wide power settings:\nCurrently in use:\n standby 1\n") == false
            && LidAwakeCommands.sleepDisabled(inPmsetOutput: "") == nil,
          "lid: pmset -g's SleepDisabled is read; its absence is normal sleep")
    check(LidAwakePolicy.verdict(settings: LidAwakeSettings(enabled: true), power: PowerSnapshot(onAC: false, batteryPercent: 90),
                                 running: [], now: Date(), lowLatched: false).verdict == .held(.onBattery),
          "lid: on battery, “Only on the power adapter” lets the Mac sleep")
    var lidEngine = LidAwakeEngine(settings: LidAwakeSettings(), record: LidAwakeRecord(ownsSleepDisabled: true), helperInstalled: true)
    check(lidEngine.launch(observed: true, power: nil, running: [], helperInstalled: true, now: Date()) == [.apply(sleepDisabled: false, interactive: true)],
          "lid: a SleepDisabled NotchHub left behind (a crash) is put back at launch")
    check(AppleScriptSource.quoted(#"a "b" \c"#) == #""a \"b\" \\c""#, "lid: the admin script's string is escaped for AppleScript")
    var lidFirst = LidAwakeEngine(settings: LidAwakeSettings(), record: LidAwakeRecord(), helperInstalled: false)
    _ = lidFirst.launch(observed: false, power: PowerSnapshot(onAC: true, batteryPercent: 80), running: [], helperInstalled: false, now: Date())
    check(lidFirst.setEnabled(true, now: Date()) == [.saveSettings, .installHelper]
            && LidAwakeHelperRule(user: "alex")?.installScript().contains("; /usr/bin/pmset") == false
            && LidAwakeHelperRule(user: "ALL") == nil,
          "lid: sleep is never turned off through the password dialog — only through the helper, once installed")
    check(LidAwakeCommands.watchdogScript(pid: 42, uid: 501, processName: "NotchHub")
            .hasSuffix("exec /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0"),
          "lid: the dead-man's switch puts normal sleep back through the helper")
    let dashboardFrame = selftestGeometry.frame(for: .interactive, content: .default)
    let dashboardChips = DashboardLayout.actions(in: dashboardFrame, notchInset: 32, focus: .nothing)
        .filter { DashboardLayout.quickActions.contains($0.action) }
        .sorted { $0.rect.minX < $1.rect.minX }
    check(dashboardChips.map(\.action) == [.lidAwake, .timer, .teleprompter, .camera, .tray]
            && dashboardChips.prefix(4).allSatisfy { $0.rect.width == DashboardLayout.glyphChipWidth }
            && NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil) != nil,
          "lid: the dashboard's lid chip is the leftmost quick action, a glyph like the timer's (this macOS draws laptopcomputer)")
    let lidOn = LidAwakeSettings(enabled: true)
    check(DashboardLidChip(LidSettingsModel(status: .normal)) == .off
            && DashboardLidChip(LidSettingsModel(settings: lidOn, status: .awake, helperInstalled: true)) == .awake
            && DashboardLidChip(LidSettingsModel(settings: lidOn, status: .held(.onBattery), helperInstalled: true)) == .waiting
            && DashboardLidChip(LidSettingsModel(status: .stillOff, helperInstalled: true)) == .waiting
            && DashboardLidChip.click(LidSettingsModel(status: .normal)) == .setEnabled(true),
          "lid: the dashboard chip is off, lit while keeping the Mac awake, dotted while paused or while sleep is still off — and a click is the Settings switch")

    print("")
    print(failures == 0 ? "SELF-TEST PASSED" : "SELF-TEST FAILED (\(failures) failures)")
    return failures == 0 ? 0 : 1
}

/// Draws a frame red on its left half and blue on its right through NEO's
/// camera preview, and says which of its two sides came out blue.
@MainActor
func selfTestCameraSides(mirrored: Bool) -> (left: Bool, right: Bool)? {
    guard let frame = selfTestSplitFrame() else { return nil }
    let stream = NeoCameraStream()
    stream.frame = frame
    let renderer = ImageRenderer(content: NeoCameraStreamPreview(stream: stream, mirrored: mirrored).frame(width: 160, height: 90))
    renderer.scale = 1
    guard let image = renderer.cgImage else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let left = rep.colorAt(x: 20, y: 45), let right = rep.colorAt(x: 140, y: 45) else { return nil }
    return (left.blueComponent > left.redComponent, right.blueComponent > right.redComponent)
}

/// A 16×9 PNG, red on its left half and blue on its right: which way round
/// the NEO camera preview draws it says whether it mirrored the picture.
func selfTestSplitFrame() -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 9, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    for x in 0..<16 {
        for y in 0..<9 {
            rep.setColor(x < 8 ? NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1) : NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: x, y: y)
        }
    }
    return rep.representation(using: .png, properties: [:])
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

// --neo-outline-frames DIR [LABEL]: NEO's wake outline frame by frame at a fixed clock — a loop,
// the entrance and exit, a real-time episode — in four island shapes on grey and white desktops
// (and an x-ray of the notch), with contact sheets and 4× zooms → DIR/LABEL (headless).
// See `NeoOutlineFrames`; `scripts/outline_gif.py` turns a frame folder into a GIF.
if arguments.contains("--neo-outline-frames") {
    exit(MainActor.assumeIsolated { NeoOutlineFrames.run(arguments: arguments) })
}

// --neo-outline-morph DIR [LABEL]: the wake outline LIVE while the island springs between shapes
// and while the light comes and goes, sampled from an invisible (alpha 0) window → DIR/LABEL/morph.
if arguments.contains("--neo-outline-morph") {
    MainActor.assumeIsolated { NeoOutlineMorph.run(arguments: arguments) }
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

// --pet-custom-snapshots DIR: everything the pet's page of Settings can change — furs, accessories,
// sizes and homes in the real island, the page itself → DIR/pet-custom.png (headless).
if let index = arguments.firstIndex(of: "--pet-custom-snapshots") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "."
    exit(MainActor.assumeIsolated { PetCustomSnapshots.render(directory: directory) })
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
