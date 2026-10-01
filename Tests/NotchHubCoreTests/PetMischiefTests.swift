import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("Pet mischief")
struct PetMischiefTests {

    let t0 = Date(timeIntervalSince1970: 3_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// Resting on the dock beside a real notch, with Mischief and Idle
    /// Animations on.
    func roaming() -> PetContext {
        var c = PetContext()
        c.canRoam = true
        c.mischief = true
        return c
    }

    /// The 14-inch MacBook Pro this app runs on.
    func geometry() -> NotchGeometry {
        NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
        )
    }

    /// Drives the brain from wakeup to wakeup, as the app does.
    @discardableResult
    func run(_ brain: inout PetBrain, _ context: PetContext, from start: TimeInterval, until end: TimeInterval,
             each: (PetBrain) -> Void = { _ in }) -> TimeInterval {
        var t = start
        brain.update(context, now: at(t))
        while t < end, let next = brain.nextWakeup(context: context, now: at(t)) {
            t = next.timeIntervalSince(t0)
            brain.update(context, now: at(t))
            each(brain)
        }
        return t
    }

    /// Plays the current mischief to its end, wakeup by wakeup.
    func finishMischief(_ brain: inout PetBrain, _ context: PetContext, from start: TimeInterval) -> TimeInterval {
        var t = start
        var beats = 0
        while brain.mischief != nil, beats < 200, let next = brain.nextWakeup(context: context, now: at(t)) {
            t = next.timeIntervalSince(t0)
            brain.update(context, now: at(t))
            beats += 1
        }
        return t
    }

    // MARK: - Schedule

    @Test("a resting pet gets up to mischief on its own schedule, and every game ends on a full dock")
    func playsOnSchedule() {
        for seed in UInt64(1)...25 {
            var brain = PetBrain(now: t0, seed: seed)
            var kinds = Set<PetMischief>()
            var wakeups = 0
            run(&brain, roaming(), from: 0, until: PetBrain.sleepAfter - 1) { b in
                wakeups += 1
                if let kind = b.mischief {
                    kinds.insert(kind)
                } else {
                    #expect(b.dock.reach == PetLayout.idleDock)
                }
            }
            #expect(!kinds.isEmpty, "seed \(seed) never played")
            #expect(wakeups < 600, "seed \(seed) woke \(wakeups) times")
        }
    }

    @Test("mischief stops for sleep, and the pet is back home to sleep")
    func sleepsAtHome() {
        for seed in UInt64(1)...25 {
            var brain = PetBrain(now: t0, seed: seed)
            run(&brain, roaming(), from: 0, until: PetBrain.sleepAfter + 30)
            #expect(brain.mischief == nil, "seed \(seed)")
            #expect(brain.dock == .home, "seed \(seed)")
            #expect(brain.presentation.mood == .sleeping, "seed \(seed)")
        }
    }

    @Test("with Mischief or Idle Animations off, or off the resting dock, the pet never leaves its spot")
    func offMeansStill() {
        for variant in 0..<3 {
            var brain = PetBrain(now: t0, seed: 11)
            var c = roaming()
            switch variant {
            case 0: c.mischief = false
            case 1: c.idleFlourishes = false
            default: c.canRoam = false
            }
            let context = c
            run(&brain, context, from: 0, until: 170) { b in
                #expect(b.mischief == nil)
                #expect(b.dock == .home)
                #expect(!b.presentation.mirrored)
                if !context.mischief {
                    #expect(![.hop, .blep, .snicker, .pounce].contains(b.presentation.animation))
                }
                if !context.canRoam {
                    #expect(b.presentation.animation != .pounce)
                }
            }
        }
    }

    // MARK: - Plans

    func expectCleanPlan(_ steps: [PetMischiefStep], label: String) {
        for step in steps {
            switch step.animation.mischiefPose {
            case .home:
                #expect(step.dock.reach == PetLayout.idleDock, "\(label): \(step.animation) on a partial dock")
            case .peeking:
                #expect(step.dock.reach == PetLayout.peekReach, "\(label): \(step.animation) peeks from a \(step.dock.reach)pt dock")
            case .hidden:
                break
            }
        }
        for (a, b) in zip(steps, steps.dropFirst()) {
            if a.dock.side != b.dock.side {
                #expect(a.dock.reach == 0 && b.dock.reach == 0, "\(label): sides swap on an open dock")
                #expect(a.animation.mischiefPose == .hidden && b.animation.mischiefPose == .hidden, "\(label): sides swap while visible")
            } else {
                if a.animation == .tailPeek {
                    #expect(b.animation == .duckTail, "\(label): a wagging tail retreats as \(b.animation)")
                }
                let end = a.animation.animation.offset(forFrame: a.animation.animation.frames.count - 1)
                let start = b.animation.animation.offset(forFrame: 0)
                #expect(abs(end.dx - start.dx) <= 5 && abs(end.dy - start.dy) <= 5, "\(label): \(a.animation) → \(b.animation) jumps")
            }
        }
        #expect(steps.last?.dock.reach == PetLayout.idleDock, "\(label): ends on a partial dock")
    }

    /// The dock's reach `t` seconds into a beat, as the island's slowest idle
    /// spring moves it (starting a frame late). A shrinking dock is judged at
    /// its smaller size throughout.
    func reach(from previous: PetDock, to target: PetDock, at t: TimeInterval) -> CGFloat {
        let start = previous.side == target.side ? previous.reach : 0
        guard target.reach > start else { return target.reach }
        let s = max(0, t - 1.0 / 60)
        let response = 0.44, damping = 0.92
        let w0 = 2 * Double.pi / response
        let wd = w0 * (1 - damping * damping).squareRoot()
        let progress = 1 - exp(-damping * w0 * s) * (cos(wd * s) + damping * w0 / wd * sin(wd * s))
        return start + (target.reach - start) * CGFloat(min(1, max(0, progress)))
    }

    /// Every lit pixel of every frame is under the physical notch or inside the
    /// black dock — never floating over the menu bar beside it.
    func expectInsideIsland(_ steps: [PetMischiefStep], notch: CGRect, label: String) {
        var previous = PetDock.home
        for step in steps {
            let animation = step.animation.animation
            let mirrored = step.dock.side == .left
            let home = mirrored ? notch.minX - PetLayout.dockInset - PetLayout.artSize : notch.maxX + PetLayout.dockInset
            for index in animation.frames.indices {
                let t = animation.isStatic ? 0 : Double(index) * animation.frameDuration
                let r = reach(from: previous, to: step.dock, at: t)
                let lo = mirrored ? notch.minX - r : notch.minX
                let hi = mirrored ? notch.maxX : notch.maxX + r
                let name = PetFrame.name(animation.frames[index], mirrored: mirrored)
                guard let frame = PetFrame.named(name) else {
                    Issue.record("\(label): missing frame \(name)")
                    return
                }
                let offset = animation.offset(forFrame: index)
                let x = home + CGFloat(mirrored ? -offset.dx : offset.dx)
                for run in frame.runs {
                    let minX = x + CGFloat(run.x)
                    let maxX = minX + CGFloat(run.length)
                    let y = 8 + offset.dy + run.y
                    if minX < lo || maxX > hi || y < 0 || y >= 32 {
                        Issue.record("\(label): \(step.animation) frame \(index) '\(name)' row \(run.y) at \(minX)...\(maxX), island \(lo)...\(hi)")
                        return
                    }
                }
            }
            previous = step.dock
        }
    }

    @Test("every game swaps sides only while hidden, never jumps, and never shows outside the island")
    func plansAreClean() {
        let notch = geometry().notchFrame
        for kind in [PetMischief.hideAndSeek, .crossOver, .zoomies] {
            for seed in UInt64(1)...20 {
                var brain = PetBrain(now: t0, seed: seed)
                brain.startMischief(kind, now: at(0))
                let label = "\(kind) seed \(seed)"
                #expect(brain.mischief == kind)
                expectCleanPlan(brain.mischiefSteps, label: label)
                expectInsideIsland(brain.mischiefSteps, notch: notch, label: label)
            }
        }
    }

    @Test("winding up from any beat is a clean, quick way home")
    func windUpFromAnyBeat() {
        let notch = geometry().notchFrame
        for kind in [PetMischief.hideAndSeek, .crossOver, .zoomies] {
            for seed in UInt64(1)...6 {
                var probe = PetBrain(now: t0, seed: seed)
                probe.startMischief(kind, now: at(0))
                for k in probe.mischiefSteps.indices {
                    var brain = PetBrain(now: t0, seed: seed)
                    brain.startMischief(kind, now: at(0))
                    let start = brain.mischiefSteps.prefix(k).reduce(0) { $0 + $1.duration } + 0.001
                    var c = roaming()
                    brain.update(c, now: at(start))
                    c.mischief = false
                    brain.update(c, now: at(start + 0.001))
                    let label = "\(kind) seed \(seed) from beat \(k)"
                    let steps = brain.mischiefSteps
                    if !steps.isEmpty {
                        expectCleanPlan(steps, label: label)
                        expectInsideIsland(steps, notch: notch, label: label)
                        #expect(steps.last?.dock == .home, "\(label)")
                    }
                    _ = finishMischief(&brain, c, from: start + 0.001)
                    #expect(brain.dock == .home, "\(label)")
                }
            }
        }
    }

    @Test("moving animations end where the next beat begins, one small step at a time")
    func pathsLineUp() {
        let hidden = PetOffset(PetLayout.hiddenOffset, 0)
        #expect(PetAnimationID.dashIn.animation.offsets.last == hidden)
        #expect(PetAnimationID.sneakIn.animation.offsets.last == hidden)
        #expect(PetAnimationID.duck.animation.offsets.last == hidden)
        #expect(PetAnimationID.hidden.animation.offset(forFrame: 0) == hidden)
        #expect(PetAnimationID.peek.animation.offsets.last == PetOffset(PetLayout.peekOffset, 0))
        for id in [PetAnimationID.dashOut, .popOut, .pounce, .hop] {
            #expect(id.animation.offsets.last == .zero, "\(id)")
        }
        for id in PetAnimationID.allCases where !id.animation.offsets.isEmpty && !id.animation.isStatic {
            let offsets = id.animation.offsets
            #expect(offsets.count == id.animation.frames.count, "\(id)")
            for (a, b) in zip(offsets, offsets.dropFirst()) {
                #expect(abs(a.dx - b.dx) <= 5 && abs(a.dy - b.dy) <= 5, "\(id) teleports")
            }
        }
    }

    // MARK: - Interruptions

    @Test("leaving the resting dock drops the game at once; the island carries the pet home")
    func leavingDropsIt() {
        var brain = PetBrain(now: t0, seed: 3)
        var c = roaming()
        brain.startMischief(.crossOver, now: at(0))
        brain.update(c, now: at(1.0))
        #expect(brain.dock.reach == 0)
        c.canRoam = false
        c.isHovering = true
        brain.update(c, now: at(1.1))
        #expect(brain.mischief == nil)
        #expect(brain.dock == .home)
        #expect(!brain.presentation.mirrored)
    }

    @Test("a real moment brings the pet straight home to react")
    func momentBringsItHome() {
        var brain = PetBrain(now: t0, seed: 3)
        let c = roaming()
        brain.startMischief(.hideAndSeek, now: at(0))
        brain.update(c, now: at(2.0))
        #expect(brain.mischief == .hideAndSeek)
        brain.handle(.timerFinished, context: c, now: at(2.1))
        #expect(brain.mischief == nil)
        #expect(brain.dock == .home)
        #expect(brain.presentation.animation == .timerDone)
    }

    @Test("a visit to the left is mirrored, and when something needs the pet it comes home")
    func visitAndReturn() {
        var brain = PetBrain(now: t0, seed: 5)
        var c = roaming()
        brain.startMischief(.crossOver, now: at(0))
        var t = finishMischief(&brain, c, from: 0)
        #expect(brain.dock == PetDock(side: .left, reach: PetLayout.idleDock))
        #expect(brain.presentation.mirrored)

        c.isAgentWorking = true
        t += 0.1
        brain.update(c, now: at(t))
        #expect(brain.mischief == .returnHome)
        t = finishMischief(&brain, c, from: t)
        #expect(brain.dock == .home)
        #expect(brain.presentation.mood == .coding)
        #expect(!brain.presentation.mirrored)
    }

    @Test("after a while on the left, the pet heads home by itself")
    func awayEnds() {
        var brain = PetBrain(now: t0, seed: 8)
        let c = roaming()
        brain.startMischief(.crossOver, now: at(0))
        let t = finishMischief(&brain, c, from: 0)
        #expect(brain.dock.side == .left)
        var wentHome = false
        run(&brain, c, from: t, until: t + PetBrain.awayStay.upperBound + 10) { b in
            if b.mischief == .returnHome { wentHome = true }
        }
        #expect(wentHome)
    }

    @Test("pointing at a peeking pet catches it: it pops out, busted")
    func caughtPeeking() {
        var brain = PetBrain(now: t0, seed: 9)
        var c = roaming()
        brain.startMischief(.hideAndSeek, now: at(0))
        let steps = brain.mischiefSteps
        let peekIndex = steps.firstIndex { $0.animation == .peek }!
        let peekTime = steps.prefix(peekIndex).reduce(0) { $0 + $1.duration } + 1.0
        brain.update(c, now: at(peekTime))
        #expect(brain.presentation.animation == .peek)
        c.isPetHovered = true
        brain.handle(.petHovered, context: c, now: at(peekTime + 0.1))
        #expect(brain.mischief == .caught)
        #expect(brain.mischiefSteps.map(\.animation) == [.popOut, .caught])
        #expect(brain.presentation.animation == .popOut)
    }

    @Test("coming to the notch mid-game is caught in the act")
    func hoverCatchesIt() {
        var brain = PetBrain(now: t0, seed: 9)
        var c = roaming()
        brain.startMischief(.crossOver, now: at(0))
        brain.update(c, now: at(0.3))
        c.canRoam = false
        c.isHovering = true
        brain.handle(.hoverEntered, context: c, now: at(0.4))
        #expect(brain.presentation.animation == .caught)
        #expect(brain.dock == .home)
    }

    // MARK: - Smoothness under interruption

    struct Drawn: CustomStringConvertible {
        let dx: Int
        let dy: Int
        /// Wholly inside the notch.
        let hidden: Bool
        /// …where cutting home reveals it as a closed dock opens: the right dock is
        /// closed, or the pet hides on the left (home's dock is closed then).
        let closed: Bool
        /// Drawn on the left of the notch.
        let left: Bool
        var description: String { "(\(dx),\(dy)\(left ? " left" : "")\(hidden ? " hidden" : "")\(closed ? " closed" : ""))" }
    }

    /// The sprite as the view draws it at `t` (mirrored on the left).
    func drawn(_ brain: PetBrain, _ t: TimeInterval) -> Drawn {
        let p = brain.presentation
        let o = p.animation.animation.offset(at: at(t).timeIntervalSince(p.startedAt))
        return Drawn(dx: p.mirrored ? -o.dx : o.dx, dy: o.dy, hidden: o.dx <= PetLayout.hiddenOffset + 3,
                     closed: brain.dock.reach == 0 || brain.dock.side == .left, left: p.mirrored)
    }

    /// Plays the brain from `start` to `end` as the app does (an update at each
    /// wakeup) and samples the drawn sprite every 10 ms. Consecutive samples may
    /// only move more than 5 px while the pet is hidden in the notch, or where a
    /// closed dock opens around it. Returns the number of jumps found.
    @discardableResult
    func expectSmooth(_ brain: inout PetBrain, _ context: PetContext, from start: TimeInterval, until end: TimeInterval,
                      after previous: Drawn? = nil, label: String) -> Int {
        var t = start
        if previous == nil {
            // As in the app, a game that starts is presented by the same update.
            brain.update(context, now: at(t))
        }
        var last = previous ?? drawn(brain, t)
        var next = brain.nextWakeup(context: context, now: at(t)).map { $0.timeIntervalSince(t0) } ?? .infinity
        var jumps = 0
        var first = previous != nil
        while t < end {
            if !first {
                t += 0.01
                while next <= t {
                    brain.update(context, now: at(next))
                    next = brain.nextWakeup(context: context, now: at(next)).map { $0.timeIntervalSince(t0) } ?? .infinity
                }
            }
            first = false
            let now = drawn(brain, t)
            let hiddenJoin = last.hidden && (now.hidden || last.closed)
            if !hiddenJoin, abs(now.dx - last.dx) > 5 || abs(now.dy - last.dy) > 5 || now.left != last.left {
                jumps += 1
                Issue.record("\(label): at \(String(format: "%.2f", t))s \(last) → \(now) as \(brain.presentation.animation)")
                if jumps >= 3 { return jumps }
            }
            last = now
        }
        return jumps
    }

    @Test("games and the idle life around them move smoothly")
    func playsSmoothly() {
        for kind in [PetMischief.hideAndSeek, .crossOver, .zoomies] {
            for seed in UInt64(1)...6 {
                var brain = PetBrain(now: t0, seed: seed)
                brain.startMischief(kind, now: at(0))
                expectSmooth(&brain, roaming(), from: 0, until: 40, label: "\(kind) seed \(seed)")
            }
        }
    }

    @Test("interrupting any beat at any moment — a catch, a moment, Mischief off — never makes the pet jump")
    func interruptionsNeverJump() {
        for kind in [PetMischief.hideAndSeek, .crossOver, .zoomies] {
            for seed in UInt64(1)...2 {
                var probe = PetBrain(now: t0, seed: seed)
                probe.startMischief(kind, now: at(0))
                let total = probe.mischiefSteps.reduce(0) { $0 + $1.duration }
                var cut = 0.02
                while cut < total {
                    for interruption in ["petHovered", "cameraOn", "timerFinished", "mischiefOff"] {
                        var brain = PetBrain(now: t0, seed: seed)
                        brain.startMischief(kind, now: at(0))
                        var c = roaming()
                        var t = 0.0
                        brain.update(c, now: at(0))
                        while let next = brain.nextWakeup(context: c, now: at(t))?.timeIntervalSince(t0), next <= cut {
                            t = next
                            brain.update(c, now: at(t))
                        }
                        let before = drawn(brain, cut)
                        switch interruption {
                        case "petHovered":
                            c.isPetHovered = true
                            brain.handle(.petHovered, context: c, now: at(cut))
                        case "cameraOn":
                            brain.handle(.cameraOn, context: c, now: at(cut))
                        case "timerFinished":
                            brain.handle(.timerFinished, context: c, now: at(cut))
                        default:
                            c.mischief = false
                            brain.update(c, now: at(cut))
                        }
                        let label = "\(kind) seed \(seed) \(interruption) at \(String(format: "%.2f", cut))s"
                        if expectSmooth(&brain, c, from: cut, until: cut + 7, after: before, label: label) > 0 { return }
                    }
                    cut += 0.13
                }
            }
        }
    }

    @Test("catching a peek that is still sliding out lets it finish before popping out; a hidden pet can't be caught")
    func catchRules() {
        var brain = PetBrain(now: t0, seed: 9)
        var c = roaming()
        brain.startMischief(.hideAndSeek, now: at(0))
        let steps = brain.mischiefSteps
        let peekIndex = steps.firstIndex { $0.animation == .peek }!
        let peekStart = steps.prefix(peekIndex).reduce(0) { $0 + $1.duration }
        c.isPetHovered = true
        brain.update(c, now: at(1.9))
        #expect(brain.mischiefSteps[brain.mischiefStepIndex!].animation == .hidden)
        brain.handle(.petHovered, context: c, now: at(1.95))
        #expect(brain.mischief == .hideAndSeek)

        brain.update(roaming(), now: at(peekStart + 0.05))
        #expect(brain.presentation.animation == .peek)
        brain.handle(.petHovered, context: c, now: at(peekStart + 0.06))
        #expect(brain.mischief == .caught)
        #expect(brain.mischiefSteps.map(\.animation) == [.peek, .popOut, .caught])
        #expect(brain.presentation.animation == .peek)
    }

    @Test("when something needs the pet on the left, it takes the quick way home")
    func forcedReturnIsQuick() {
        for seed in UInt64(1)...25 {
            var brain = PetBrain(now: t0, seed: seed)
            var c = roaming()
            brain.startMischief(.crossOver, now: at(0))
            let t = finishMischief(&brain, c, from: 0)
            c.isAgentWorking = true
            brain.update(c, now: at(t + 0.01))
            #expect(brain.mischiefSteps.map(\.animation) == [.dashIn, .hidden, .hidden, .hidden, .dashOut], "seed \(seed)")
        }
    }

    @Test("a flourish on the left never flashes another mood's pose before the pet heads home")
    func noFlashOnTheLeft() {
        var found = 0
        for seed in UInt64(1)...40 {
            var brain = PetBrain(now: t0, seed: seed)
            var c = roaming()
            brain.startMischief(.crossOver, now: at(0))
            var t = finishMischief(&brain, c, from: 0)
            func flourishingOnTheLeft(_ b: PetBrain) -> Bool {
                b.mischief == nil && b.dock.side == .left && b.presentation.mood == .idle && b.presentation.animation != .sit
            }
            while t < 40, !flourishingOnTheLeft(brain), let next = brain.nextWakeup(context: c, now: at(t)) {
                t = next.timeIntervalSince(t0)
                brain.update(c, now: at(t))
            }
            guard flourishingOnTheLeft(brain) else { continue }
            found += 1
            c.isAgentWorking = true
            run(&brain, c, from: t + 0.02, until: t + 10) { b in
                if b.presentation.mirrored {
                    #expect(b.presentation.mood != .coding, "seed \(seed): a mirrored coding pose")
                }
            }
            #expect(brain.dock == .home, "seed \(seed)")
        }
        #expect(found > 0)
    }

    @Test("coming to the notch while the pet is away never cuts off a celebration")
    func hoverKeepsCelebration() {
        var brain = PetBrain(now: t0, seed: 5)
        var c = roaming()
        brain.startMischief(.crossOver, now: at(0))
        let t = finishMischief(&brain, c, from: 0)
        brain.handle(.timerFinished, context: c, now: at(t + 0.1))
        #expect(brain.presentation.animation == .timerDone)
        c.canRoam = false
        c.isHovering = true
        brain.handle(.hoverEntered, context: c, now: at(t + 0.3))
        #expect(brain.presentation.animation == .timerDone)
        #expect(brain.dock == .home)
    }

    @Test("a pounce stops when the island leaves the resting dock")
    func pounceStaysOnTheDock() {
        var found = false
        for seed in UInt64(1)...80 where !found {
            var brain = PetBrain(now: t0, seed: seed)
            var c = roaming()
            var t = 0.0
            brain.update(c, now: at(0))
            while t < 170, brain.presentation.animation != .pounce, let next = brain.nextWakeup(context: c, now: at(t)) {
                t = next.timeIntervalSince(t0)
                brain.update(c, now: at(t))
            }
            guard brain.presentation.animation == .pounce else { continue }
            found = true
            c.canRoam = false
            c.isHovering = true
            brain.update(c, now: at(t + 0.3))
            #expect(brain.presentation.animation != .pounce)
        }
        #expect(found)
    }

    // MARK: - Review fixes carried along

    @Test("an ignored notification neither wakes a pet put to sleep nor counts as engagement")
    func ignoredNotificationKeepsSleep() {
        var brain = PetBrain(now: t0)
        let c = PetContext()
        brain.handle(.interaction(.sleep), context: c, now: at(1))
        brain.handle(.notification(important: false), context: c, now: at(20))
        #expect(brain.presentation.mood == .sleeping)

        var natural = PetBrain(now: t0)
        natural.update(c, now: at(0))
        natural.handle(.notification(important: false), context: c, now: at(PetBrain.sleepAfter - 10))
        natural.update(c, now: at(PetBrain.sleepAfter + 1))
        #expect(natural.presentation.mood == .sleeping)
    }

    @Test("hovering for ages with Idle Animations off still counts from when it ended")
    func hoverEndCounts() {
        var brain = PetBrain(now: t0)
        var c = PetContext()
        c.idleFlourishes = false
        c.isHovering = true
        brain.update(c, now: at(0))
        c.isHovering = false
        brain.update(c, now: at(600))
        #expect(brain.presentation.mood != .sleeping)
    }

    // MARK: - Geometry

    @Test("the idle island follows the dock to either side of the notch")
    func dockGeometry() {
        let g = geometry()
        let notch = g.notchFrame
        var content = IslandContentSize.default
        content.petDock = PetDock(side: .left, reach: PetLayout.idleDock)
        let left = g.frame(for: .idle, content: content)
        #expect(left.minX == notch.minX - PetLayout.idleDock)
        #expect(left.maxX == notch.maxX)
        content.petDock = PetDock(side: .right, reach: 0)
        #expect(g.frame(for: .idle, content: content) == notch)
        content.petDock = PetDock(side: .right, reach: PetLayout.peekReach)
        #expect(g.frame(for: .idle, content: content).maxX == notch.maxX + PetLayout.peekReach)

        let placement = PetLayout.placement(for: .idle, islandSize: left.size, notchHeight: 32, dock: PetDock(side: .left, reach: PetLayout.idleDock))!
        #expect(placement.anchor == .leading)
        #expect(left.minX + placement.origin.x + placement.size == notch.minX - PetLayout.dockInset)

        let docked = g.compactBar(lead: 0, trail: PetLayout.idleDock)
        #expect(IslandMotion.between(from: notch, fromIdle: true, to: docked, toIdle: true) == .peek)
        #expect(IslandMotion.between(from: docked, fromIdle: true, to: notch, toIdle: true) == .collapse)
        #expect(IslandMotion.between(from: docked, fromIdle: true, to: g.compactBar(lead: PetLayout.idleDock, trail: 0), toIdle: true) == .morph)
    }

    @Test("the pet panel's content is centred, wherever the pet was when it was clicked")
    func panelContentIsCentred() {
        let g = geometry()
        let panel = g.petPanelFrame
        let chips = PetPanelLayout.actions(in: panel, notchInset: 32)
        let petWidth = PetLayout.artSize * PetPanelLayout.petScale
        let contentMinX = PetPanelLayout.contentMinX(in: panel)
        // The whole block — big pet, then the chips — is centred in the panel.
        #expect(abs((contentMinX + PetPanelLayout.contentWidth / 2) - panel.midX) < 1)
        #expect(chips.first!.rect.minX == contentMinX + petWidth + PetPanelLayout.spacing)
        #expect(abs(chips.last!.rect.maxX - (contentMinX + PetPanelLayout.contentWidth)) < 1)
        for chip in chips {
            #expect(panel.contains(chip.rect))
            let centre = CGPoint(x: chip.rect.midX, y: chip.rect.midY)
            #expect(PetPanelLayout.action(at: centre, in: panel, notchInset: 32) == chip.action)
        }
    }

    @Test("settings saved before Mischief existed keep their values")
    func settingsMigrate() throws {
        let saved = #"{"showPet":true,"reactions":false,"idleAnimations":true,"interaction":false}"#
        let settings = try JSONDecoder().decode(PetSettings.self, from: Data(saved.utf8))
        #expect(settings.reactions == false)
        #expect(settings.interaction == false)
        #expect(settings.mischief == true)
    }
}
