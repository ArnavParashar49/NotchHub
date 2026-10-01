import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("Pet frames and animations")
struct PetFrameTests {

    @Test("rows decode into runs of same-coloured pixels; '.' is transparent")
    func decodesRuns() {
        let rows = ["kkoo." + String(repeating: ".", count: 11)] + Array(repeating: String(repeating: ".", count: 16), count: 15)
        let frame = PetFrame(rows: rows, palette: ["k": 0x111111, "o": 0xFF8800])
        #expect(frame.runs == [
            PetFrame.Run(x: 0, y: 0, length: 2, color: 0x111111),
            PetFrame.Run(x: 2, y: 0, length: 2, color: 0xFF8800),
        ])
    }

    @Test("a loop wraps, a one-shot holds its last frame, a still never animates")
    func timing() {
        let loop = PetAnimation.loop(["a", "b", "c"], 0.5)
        #expect(loop.frameName(at: 0) == "a")
        #expect(loop.frameName(at: 1.2) == "c")
        #expect(loop.frameName(at: 1.6) == "a")
        #expect(loop.isAnimating(at: 100))

        let once = PetAnimation.once(["a", "b"], 0.5)
        #expect(once.frameName(at: 5) == "b")
        #expect(!once.isAnimating(at: 1.0))
        #expect(once.duration == 1.0)

        let still = PetAnimation.still("sit")
        #expect(still.isStatic)
        #expect(!still.isAnimating(at: 0))
    }

    @Test("every frame an animation uses exists in the art set")
    func artIsComplete() {
        let missing = PetAnimationID.allCases
            .flatMap { id in id.animation.frames.map { (id, $0) } }
            .filter { PetFrame.named($0.1) == nil }
            .map { "\($0.0.rawValue): \($0.1)" }
        #expect(missing.isEmpty, "missing frames: \(missing)")
    }

    @Test("every art frame is exactly 16×16")
    func artDimensions() {
        for (name, rows) in PetArt.frames {
            #expect(rows.count == 16, "\(name) has \(rows.count) rows")
            #expect(rows.allSatisfy { $0.count == 16 }, "\(name) has a row that is not 16 wide")
        }
    }
}

@Suite("PetBrain")
struct PetBrainTests {

    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test("a new pet sits calmly")
    func startsIdle() {
        let brain = PetBrain(now: t0)
        #expect(brain.presentation.mood == .idle)
        #expect(brain.presentation.animation == .sit)
    }

    @Test("with nothing happening it falls asleep, and a hover wakes it")
    func sleepsAndWakes() {
        var brain = PetBrain(now: t0)
        var context = PetContext()
        brain.update(context, now: at(PetBrain.sleepAfter + 1))
        #expect(brain.presentation.mood == .sleeping)
        #expect([.sleep, .sleepZzz].contains(brain.presentation.animation))

        context.isHovering = true
        brain.update(context, now: at(PetBrain.sleepAfter + 2))
        #expect(brain.presentation.animation == .wake)
        brain.update(context, now: at(PetBrain.sleepAfter + 4))
        #expect(brain.presentation.mood == .curious)
    }

    @Test("context picks the mood by priority")
    func moodPriority() {
        var brain = PetBrain(now: t0)
        var context = PetContext()
        context.isMusicPlaying = true
        brain.update(context, now: at(1))
        #expect(brain.presentation.mood == .music)
        #expect(brain.presentation.animation == .music)

        context.isAgentWorking = true
        brain.update(context, now: at(2))
        #expect(brain.presentation.mood == .coding)

        context.inMeeting = true
        context.meetingMuted = true
        brain.update(context, now: at(3))
        #expect(brain.presentation.animation == .meetingMuted)

        context.interactionOpen = true
        brain.update(context, now: at(4))
        #expect(brain.presentation.mood == .interaction)
    }

    @Test("a celebration plays, then the pet returns to what it was doing")
    func reactionReturns() {
        var brain = PetBrain(now: t0)
        var context = PetContext()
        context.isTimerRunning = true
        brain.update(context, now: at(1))
        context.isTimerRunning = false
        brain.handle(.timerFinished, context: context, now: at(2))
        #expect(brain.presentation.mood == .celebrating)
        #expect(brain.presentation.animation == .timerDone)

        let end = brain.nextWakeup(context: context, now: at(2))
        #expect(end == at(2 + PetAnimationID.timerDone.animation.duration))
        brain.update(context, now: at(10))
        #expect(brain.presentation.mood == .idle)
    }

    @Test("a minor reaction never cuts off a celebration")
    func minorDoesNotInterrupt() {
        var brain = PetBrain(now: t0)
        let context = PetContext()
        brain.handle(.downloadFinished, context: context, now: at(1))
        brain.handle(.notification(important: true), context: context, now: at(1.1))
        #expect(brain.presentation.animation == .downloadDone)
    }

    @Test("trivial notifications are ignored; important ones are noticed")
    func notificationPriority() {
        var brain = PetBrain(now: t0)
        let context = PetContext()
        brain.handle(.notification(important: false), context: context, now: at(1))
        #expect(brain.presentation.mood == .idle)
        brain.handle(.notification(important: true), context: context, now: at(2))
        #expect(brain.presentation.animation == .notify)
    }

    @Test("hover reactions are rate-limited")
    func hoverCooldown() {
        var brain = PetBrain(now: t0)
        var context = PetContext()
        context.isHovering = true
        brain.handle(.hoverEntered, context: context, now: at(1))
        let first = brain.presentation.animation
        #expect([.tailWag, .wave, .jump].contains(first))
        brain.update(context, now: at(3))
        brain.handle(.hoverEntered, context: context, now: at(3.2))
        #expect(![.tailWag, .wave, .jump].contains(brain.presentation.animation))
    }

    @Test("the same seed gives the same personality")
    func deterministic() {
        func run() -> [PetAnimationID] {
            var brain = PetBrain(now: t0, seed: 42)
            let context = PetContext()
            return stride(from: 0.0, through: 120, by: 0.25).map { brain.update(context, now: at($0)).animation }
        }
        #expect(run() == run())
        #expect(Set(run()).count > 1, "idle life should include flourishes")
    }

    @Test("idle life is mostly calm")
    func mostlyCalm() {
        var brain = PetBrain(now: t0, seed: 7)
        let context = PetContext()
        let samples = stride(from: 0.0, through: 170, by: 0.1).map { brain.update(context, now: at($0)).animation }
        let calm = samples.filter { $0 == .sit }.count
        #expect(Double(calm) / Double(samples.count) > 0.6)
    }

    @Test("putting the pet to sleep holds until something engages it")
    func sleepInteraction() {
        var brain = PetBrain(now: t0)
        var context = PetContext()
        brain.handle(.interaction(.sleep), context: context, now: at(1))
        brain.update(context, now: at(5))
        #expect(brain.presentation.mood == .sleeping)
        context.isMusicPlaying = true
        brain.update(context, now: at(6))
        #expect(brain.presentation.animation == .wake)
    }

    @Test("an idle pet schedules its next moment instead of polling")
    func schedulesWakeups() {
        var brain = PetBrain(now: t0)
        let context = PetContext()
        brain.update(context, now: at(0))
        let wake = brain.nextWakeup(context: context, now: at(0))
        #expect(wake != nil)
        #expect(wake! > at(0))
        #expect(wake! <= at(PetBrain.sleepAfter))
    }
}

@Suite("PetLayout")
struct PetLayoutTests {

    @Test("in notch-height bars the pet is right-anchored at 1x and vertically centred")
    func bars() {
        for state in [IslandState.idle, .wings, .compact] {
            let size = CGSize(width: 300, height: 32)
            let p = PetLayout.placement(for: state, islandSize: size, notchHeight: 32)
            #expect(p?.scale == 1)
            #expect(p!.origin.y == 8)
            #expect(p!.origin.x + p!.size < size.width)
            #expect(p!.origin.x + p!.size >= size.width - 20)
        }
    }

    @Test("the pet rides the right edge: a wider island moves it by exactly the difference")
    func ridesTheEdge() {
        let narrow = PetLayout.placement(for: .compact, islandSize: CGSize(width: 300, height: 32), notchHeight: 32)!
        let wide = PetLayout.placement(for: .compact, islandSize: CGSize(width: 420, height: 32), notchHeight: 32)!
        #expect(wide.origin.x - narrow.origin.x == 120)
    }

    @Test("the expanded island shows a 2x pet below the notch; utility panels hide it")
    func expandedAndHidden() {
        let p = PetLayout.placement(for: .expanded, islandSize: CGSize(width: 587, height: 88), notchHeight: 32)!
        #expect(p.scale == 2)
        #expect(p.origin.y >= 32)
        #expect(p.origin.y + p.size <= 88)
        for state in [IslandState.tray, .settings, .teleprompter, .fileDrop] {
            #expect(PetLayout.placement(for: state, islandSize: CGSize(width: 400, height: 400), notchHeight: 32) == nil)
        }
    }

    @Test("panels keep the pet in the notch strip, clear of the '···'")
    func panelsStrip() {
        let size = CGSize(width: 440, height: 196)
        let p = PetLayout.placement(for: .interactive, islandSize: size, notchHeight: 32)!
        let more = size.width - DashboardLayout.horizontalInset - DashboardLayout.moreSize.width
        #expect(p.origin.x + p.size <= more)
        #expect(p.origin.y + p.size <= 32)
    }
}

@Suite("The pet is NEO")
struct PetIsNeoTests {

    let t0 = Date(timeIntervalSince1970: 2_000_000)
    func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func context(_ state: NeoState?) -> PetContext {
        var c = PetContext()
        c.neoState = state
        c.canRoam = true
        c.isDocked = true
        c.mischief = true
        return c
    }

    @Test("the pet is named Neo")
    func name() {
        #expect(PetIdentity.name == "Neo")
        #expect(PetIdentity.hello == "Hi, I'm Neo!")
    }

    @Test("each of NEO's states is a pose of its own; ready is the pet's own life")
    func poses() {
        #expect(PetBrain.neoAnimation(for: .connecting) == .neoWake)
        #expect(PetBrain.neoAnimation(for: .listening) == .neoListen)
        #expect(PetBrain.neoAnimation(for: .thinking) == .neoThink)
        #expect(PetBrain.neoAnimation(for: .working) == .neoPace)
        #expect(PetBrain.neoAnimation(for: .searching) == .neoSniff)
        #expect(PetBrain.neoAnimation(for: .speaking) == .neoTalk)
        #expect(PetBrain.neoAnimation(for: .confirming) == .neoAsk)
        #expect(PetBrain.neoAnimation(for: .idle) == .sit)
        // The busy poses move on their own: loops, or a wake that holds its last frame.
        for state in NeoState.allCases where state != .idle {
            let animation = PetBrain.neoAnimation(for: state).animation
            #expect(animation.loops || !animation.isStatic, "\(state)")
        }
        // Pacing stays within the dock: never under the notch, never off its edge.
        for offset in PetAnimationID.neoPace.animation.offsets {
            #expect(offset.dx <= 0 && offset.dx > PetLayout.hiddenOffset + 10 && abs(offset.dy) <= 1)
        }
    }

    @Test("while NEO is busy the pet poses as NEO, over the cursor and every activity; ready, it is itself")
    func busyOverEverything() {
        var brain = PetBrain(now: t0)
        var c = context(.speaking)
        c.isHovering = true
        c.isMusicPlaying = true
        c.isAgentWorking = true
        #expect(brain.update(c, now: t0).mood == .neo)
        #expect(brain.presentation.animation == .neoTalk)
        c.neoState = .thinking
        #expect(brain.update(c, now: at(1)).animation == .neoThink)
        c.neoState = .idle
        c.isHovering = false
        c.isMusicPlaying = false
        c.isAgentWorking = false
        let ready = brain.update(c, now: at(2))
        #expect(ready.mood == .idle && ready.animation == .sit)
        c.neoState = nil // NEO away: the same
        #expect(brain.update(c, now: at(3)).mood == .idle)
    }

    @Test("NEO starting wakes a pet put to sleep, and stops a game on the dock")
    func wakesAndStopsMischief() {
        var brain = PetBrain(now: t0)
        var c = context(.idle)
        brain.handle(.interaction(.sleep), context: c, now: t0)
        #expect(brain.update(c, now: at(1)).mood == .sleeping)
        c.neoState = .listening
        _ = brain.update(c, now: at(2))
        // Waking is a moment (the wake animation), then the pose.
        _ = brain.update(c, now: at(2 + PetAnimationID.wake.animation.duration + 0.1))
        #expect(brain.presentation.mood == .neo && brain.presentation.animation == .neoListen)

        var playing = PetBrain(now: t0)
        c.neoState = .idle
        playing.startMischief(.hideAndSeek, now: t0)
        #expect(playing.mischief == .hideAndSeek)
        c.neoState = .working
        var now = at(0.1)
        // The game finishes its beat and comes home; then the pet is NEO.
        for _ in 0..<60 {
            _ = playing.update(c, now: now)
            guard playing.mischief != nil else { break }
            now = playing.nextWakeup(context: c, now: now) ?? now.addingTimeInterval(0.5)
        }
        #expect(playing.mischief == nil && playing.dock == .home)
        #expect(playing.update(c, now: now.addingTimeInterval(0.1)).animation == .neoPace)
    }

    @Test("the pet's panel and a call still come first; NEO's pose returns after them")
    func panelAndMeetingFirst() {
        var brain = PetBrain(now: t0)
        var c = context(.speaking)
        c.interactionOpen = true
        #expect(brain.update(c, now: t0).mood == .interaction)
        c.interactionOpen = false
        c.inMeeting = true
        #expect(brain.update(c, now: at(1)).mood == .meeting)
        c.inMeeting = false
        #expect(brain.update(c, now: at(2)).mood == .neo)
    }
}
