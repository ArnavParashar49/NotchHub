import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("Pet looks, hats, tricks and touch")
struct PetTouchTests {

    let t0 = Date(timeIntervalSince1970: 4_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    static let inPlaceTricks: [PetAnimationID] = [.hop, .blep, .snicker, .wave, .jump, .heart]

    // MARK: - Looks and hats

    @Test("seasonal hats follow the calendar")
    func seasons() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }
        #expect(PetHat.seasonal(on: day(10, 20), calendar: calendar) == .witch)
        #expect(PetHat.seasonal(on: day(10, 16), calendar: calendar) == nil)
        #expect(PetHat.seasonal(on: day(12, 5), calendar: calendar) == .santa)
        #expect(PetHat.seasonal(on: day(12, 31), calendar: calendar) == .party)
        #expect(PetHat.seasonal(on: day(1, 2), calendar: calendar) == .party)
        #expect(PetHat.seasonal(on: day(3, 25), calendar: calendar) == .flowers)
        #expect(PetHat.seasonal(on: day(9, 14), calendar: calendar) == nil)
        #expect(PetHatChoice.none.hat(on: day(12, 5), calendar: calendar) == nil)
        #expect(PetHatChoice.witch.hat(on: day(9, 14), calendar: calendar) == .witch)
    }

    @Test("the hat button cycles through every choice and back")
    func hatCycle() {
        var choice = PetHatChoice.seasonal
        var seen = Set<PetHatChoice>()
        for _ in PetHatChoice.allCases {
            seen.insert(choice)
            choice = choice.next
        }
        #expect(seen.count == PetHatChoice.allCases.count)
        #expect(choice == .seasonal)
    }

    @Test("the fox look draws the art's own colours; other looks only recolour the fox")
    func looks() {
        for (_, rgb) in PetArt.palette {
            #expect(PetLook.fox.color(rgb) == rgb)
        }
        let foxKeys: Set<Character> = ["o", "O", "y", "k", "w", "W", "e"]
        for (name, overrides) in PetArt.looks {
            #expect(PetLook(rawValue: name) != nil, "look \(name) has no PetLook")
            for key in overrides.keys {
                #expect(foxKeys.contains(key), "look \(name) recolours prop key \(key)")
            }
        }
    }

    @Test("hat anchors mirror with their frame, and every hat and anchored frame exists")
    func anchors() {
        for hat in PetHat.allCases where !PetArt.hatAnchors.isEmpty {
            #expect(PetFrame.named(hat.frameName) != nil, "missing \(hat.frameName)")
        }
        for (name, anchor) in PetArt.hatAnchors {
            #expect(PetFrame.named(name) != nil, "anchor for unknown frame \(name)")
            let mirrored = PetFrame.hatAnchor(for: name + PetFrame.mirrorSuffix)
            #expect(mirrored?.x == PetFrame.size - anchor[0] && mirrored?.y == anchor[1])
        }
    }

    @Test("settings keep a look and hat, and fall back from ones a newer build saved")
    func settingsLookHat() throws {
        var settings = PetSettings()
        settings.look = .arctic
        settings.hat = .witch
        let back = try JSONDecoder().decode(PetSettings.self, from: JSONEncoder().encode(settings))
        #expect(back.look == .arctic)
        #expect(back.hat == .witch)
        let future = #"{"showPet":false,"look":"galaxy","hat":"crown"}"#
        let fallback = try JSONDecoder().decode(PetSettings.self, from: Data(future.utf8))
        #expect(fallback.showPet == false)
        #expect(fallback.look == .fox)
        #expect(fallback.hat == .seasonal)
    }

    // MARK: - Panel

    @Test("every panel target sits inside the panel, below the notch, apart from the others, and hits itself")
    func panelTargets() {
        let g = NotchGeometry.make(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
        )
        #expect(g.skinFrame.width >= PetPanelLayout.panelWidth)
        let notch = g.notchFrame
        // The panel is centred whatever opened it, so `skinFrame` IS the panel.
        for frame in [g.skinFrame, g.petPanelFrame] {
            #expect(g.envelopeFrame.contains(frame))
            let layout = PetPanelLayout.layout(in: frame, notchInset: 32)
            // The big pet (and the hat and hop above it) stays beside the notch.
            #expect(layout.pet.maxX <= notch.minX || layout.pet.minX >= notch.maxX, "big pet under the notch (\(frame))")
            let targets: [(PetPanelLayout.Hit, CGRect)] = layout.actions.map { (.action($0.action), $0.rect) }
                + layout.looks.map { (.look($0.look), $0.rect) }
                + [(.hat, layout.hat), (.pet, layout.pet)]
            #expect(layout.actions.map(\.action) == PetInteraction.allCases)
            #expect(layout.looks.map(\.look) == PetLook.allCases)
            for (index, target) in targets.enumerated() {
                let (hit, rect) = target
                #expect(frame.contains(rect), "\(hit) outside the panel")
                #expect(rect.maxY <= frame.maxY - 32, "\(hit) under the notch")
                #expect(PetPanelLayout.hit(at: CGPoint(x: rect.midX, y: rect.midY), in: frame, notchInset: 32) == hit)
                for other in targets[(index + 1)...] {
                    #expect(!rect.intersects(other.1), "\(hit) overlaps \(other.0)")
                }
            }
        }
    }

    @Test("with an 8-row hat, no 1x frame of any animation puts the hat above the island on a 32 pt notch")
    func hatsStayOnScreen() {
        let hatTop = PetHat.allCases.compactMap { PetFrame.named($0.frameName)?.runs.map(\.y).min() }.min() ?? 8
        let stripY = 8
        for id in PetAnimationID.allCases {
            let animation = id.animation
            for index in animation.frames.indices {
                guard let anchor = PetFrame.hatAnchor(for: animation.frames[index]) else { continue }
                let top = stripY + animation.offset(forFrame: index).dy + anchor.y - 15 + hatTop
                #expect(top >= 0, "\(id) frame \(index) '\(animation.frames[index])': hat top at \(top)")
            }
        }
    }

    // MARK: - Tricks

    @Test("Tricks plays a game once the island rests — even with Mischief off — and gives up after a while")
    func trickRequest() {
        var brain = PetBrain(now: t0, seed: 3)
        var c = PetContext()
        c.isDocked = true
        c.interactionOpen = true
        brain.handle(.interaction(.trick), context: c, now: at(1))
        #expect(brain.mischief == nil)

        c.interactionOpen = false
        c.isHovering = true
        brain.update(c, now: at(2))
        #expect(brain.mischief == nil)

        c.isHovering = false
        c.canRoam = true
        brain.update(c, now: at(3))
        #expect(brain.mischief != nil)
        let planned = brain.mischiefSteps.count
        brain.update(c, now: at(3.05))
        #expect(brain.mischiefSteps.count == planned, "a requested game must not wind up just because Mischief is off")

        var late = PetBrain(now: t0, seed: 3)
        var open = PetContext()
        open.isDocked = true
        open.interactionOpen = true
        late.handle(.interaction(.trick), context: open, now: at(1))
        var rest = PetContext()
        rest.isDocked = true
        rest.canRoam = true
        late.update(rest, now: at(1 + PetBrain.requestWindow + 1))
        #expect(late.mischief == nil)
    }

    @Test("without a dock beside a notch, Tricks plays a trick right there")
    func trickInPlace() {
        var brain = PetBrain(now: t0, seed: 5)
        var c = PetContext()
        c.interactionOpen = true
        brain.handle(.interaction(.trick), context: c, now: at(1))
        #expect(Self.inPlaceTricks.contains(brain.presentation.animation))
    }

    @Test("with Mischief off, pointing at a requested game on the left catches it there, and its visit stays")
    func requestedGameOnTheLeft() {
        var caughtOnLeft = false
        var stayed = false
        for seed in UInt64(1)...40 where !(caughtOnLeft && stayed) {
            var brain = PetBrain(now: t0, seed: seed)
            var c = PetContext()
            c.isDocked = true
            c.interactionOpen = true
            brain.handle(.interaction(.trick), context: c, now: at(1))
            c.interactionOpen = false
            c.canRoam = true
            var t = 2.0
            brain.update(c, now: at(t))
            // Play until the pet stands on the left after a game, or the game is over.
            func standingLeft(_ b: PetBrain) -> Bool {
                b.dock.side == .left && b.dock.reach == PetLayout.idleDock && b.presentation.mirrored
                    && b.presentation.animation.animation.offset(at: at(t).timeIntervalSince(b.presentation.startedAt)) == .zero
                    && [.blep, .snicker, .sit, .dashOut].contains(b.presentation.animation)
            }
            while brain.mischief != nil, !standingLeft(brain), let next = brain.nextWakeup(context: c, now: at(t)) {
                t = next.timeIntervalSince(t0) + 0.3
                brain.update(c, now: at(t))
            }
            guard standingLeft(brain) else { continue }
            if brain.mischief != nil, !caughtOnLeft {
                var pointed = c
                pointed.isPetHovered = true
                var copy = brain
                copy.handle(.petHovered, context: pointed, now: at(t + 0.01))
                #expect(copy.dock.side == .left, "seed \(seed): pointing swapped the dock's side")
                #expect(copy.presentation.mirrored, "seed \(seed)")
                caughtOnLeft = copy.mischief == .caught
            }
            // Let the game finish, then the visit should last.
            while brain.mischief != nil, let next = brain.nextWakeup(context: c, now: at(t)) {
                t = next.timeIntervalSince(t0)
                brain.update(c, now: at(t))
            }
            guard brain.dock.side == .left, brain.mischief == nil else { continue }
            let arrived = t
            while t < arrived + PetBrain.awayStay.lowerBound - 0.5, let next = brain.nextWakeup(context: c, now: at(t)) {
                t = min(next.timeIntervalSince(t0), arrived + PetBrain.awayStay.lowerBound - 0.5)
                brain.update(c, now: at(t))
            }
            #expect(brain.dock.side == .left, "seed \(seed): the requested visit ended at once")
            stayed = true
        }
        #expect(caughtOnLeft)
        #expect(stayed)
    }

    @Test("with Mischief off, a requested game caught on the left still gets its visit once the cursor leaves")
    func caughtRequestedVisit() {
        var tested = false
        for seed in UInt64(1)...40 where !tested {
            var brain = PetBrain(now: t0, seed: seed)
            var c = PetContext()
            c.isDocked = true
            c.interactionOpen = true
            brain.handle(.interaction(.trick), context: c, now: at(1))
            c.interactionOpen = false
            c.canRoam = true
            var t = 2.0
            brain.update(c, now: at(t))
            func standingLeft(_ b: PetBrain) -> Bool {
                b.dock.side == .left && b.dock.reach == PetLayout.idleDock && b.presentation.mirrored
                    && b.presentation.animation.animation.offset(at: at(t).timeIntervalSince(b.presentation.startedAt)) == .zero
                    && [.blep, .snicker, .sit, .dashOut].contains(b.presentation.animation)
            }
            while brain.mischief != nil, !standingLeft(brain), let next = brain.nextWakeup(context: c, now: at(t)) {
                t = next.timeIntervalSince(t0) + 0.3
                brain.update(c, now: at(t))
            }
            guard brain.mischief != nil, standingLeft(brain) else { continue }
            var pointed = c
            pointed.isPetHovered = true
            t += 0.01
            brain.handle(.petHovered, context: pointed, now: at(t))
            guard brain.mischief == .caught else { continue }
            // Keep pointing until the caught beat is over.
            while brain.mischief != nil, let next = brain.nextWakeup(context: pointed, now: at(t)) {
                t = next.timeIntervalSince(t0)
                brain.update(pointed, now: at(t))
            }
            #expect(brain.dock.side == .left, "seed \(seed)")
            // The cursor leaves: the visit should last.
            let leftAt = t
            t += 0.01
            brain.update(c, now: at(t))
            while t < leftAt + PetBrain.awayStay.lowerBound - 0.5, let next = brain.nextWakeup(context: c, now: at(t)) {
                t = min(next.timeIntervalSince(t0), leftAt + PetBrain.awayStay.lowerBound - 0.5)
                brain.update(c, now: at(t))
            }
            #expect(brain.dock.side == .left && brain.mischief == nil, "seed \(seed): the caught visit ended at once")
            tested = true
        }
        #expect(tested)
    }

    @Test("rapid clicks never play the same trick twice in a row")
    func rapidClicks() {
        for seed in UInt64(1)...40 {
            var brain = PetBrain(now: t0, seed: seed)
            var c = PetContext()
            c.interactionOpen = true
            brain.handle(.bigPetClicked, context: c, now: at(0))
            guard brain.presentation.animation == .hop else { continue }
            brain.handle(.bigPetClicked, context: c, now: at(0.15))
            brain.handle(.bigPetClicked, context: c, now: at(0.30))
            var played: [PetAnimationID] = [.hop]
            var t = 0.30
            while t < 4, let next = brain.nextWakeup(context: c, now: at(t)) {
                t = next.timeIntervalSince(t0)
                brain.update(c, now: at(t))
                let animation = brain.presentation.animation
                if Self.inPlaceTricks.contains(animation), animation != played.last {
                    played.append(animation)
                }
            }
            for (a, b) in zip(played, played.dropFirst()) {
                #expect(a != b, "seed \(seed): \(played)")
            }
        }
    }

    @Test("a long stroke never lets a flourish fire the instant it ends")
    func longStroke() {
        var brain = PetBrain(now: t0)
        var c = PetContext()
        c.interactionOpen = true
        c.isPetHovered = true
        var t = 1.0
        while t < 26 {
            brain.handle(.bigPetStroked, context: c, now: at(t))
            t += 0.8
        }
        c.isPetHovered = false
        brain.update(c, now: at(t - 0.8 + PetBrain.strokeHold + 0.1))
        #expect(brain.presentation.animation == .happy)
    }

    @Test("jitter on a single pass is not a stroke; slow, fine strokes are")
    func strokeDetectorEdges() {
        var jitter = PetStrokeDetector()
        var t = t0
        var stroked = false
        for x in [0, 2, 4, 6, 8, 7.4, 9, 11, 13, 15, 14.4, 16] as [CGFloat] {
            t = t.addingTimeInterval(0.02)
            if jitter.move(to: x, at: t) { stroked = true }
        }
        #expect(!stroked)

        var slow = PetStrokeDetector()
        t = t0
        stroked = false
        var x: CGFloat = 0
        var step: CGFloat = 0.4
        for _ in 0..<360 {
            x += step
            if x >= 24 || x <= 0 { step = -step }
            t = t.addingTimeInterval(1.0 / 120)
            if slow.move(to: x, at: t) { stroked = true }
        }
        #expect(stroked)
    }

    @Test("clicking the big pet plays a trick in place, never the same one twice in a row")
    func clickTricks() {
        var brain = PetBrain(now: t0, seed: 9)
        var c = PetContext()
        c.interactionOpen = true
        var last: PetAnimationID?
        for i in 0..<12 {
            brain.handle(.bigPetClicked, context: c, now: at(Double(i) * 2))
            let animation = brain.presentation.animation
            #expect(Self.inPlaceTricks.contains(animation))
            #expect(animation != last)
            last = animation
        }
    }

    // MARK: - Touch

    @Test("the big pet leans toward a pointing cursor and purrs while stroked, without restarting")
    func strokeAndLean() {
        var brain = PetBrain(now: t0)
        var c = PetContext()
        c.interactionOpen = true
        c.isPetHovered = true
        c.cursorSide = .left
        brain.update(c, now: at(1))
        #expect(brain.presentation.animation == .leanLeft)
        c.cursorSide = .right
        brain.update(c, now: at(1.1))
        #expect(brain.presentation.animation == .leanRight)

        brain.handle(.bigPetStroked, context: c, now: at(2))
        #expect(brain.presentation.animation == .stroke)
        let started = brain.presentation.startedAt
        brain.handle(.bigPetStroked, context: c, now: at(2.8))
        brain.handle(.bigPetStroked, context: c, now: at(3.6))
        #expect(brain.presentation.animation == .stroke)
        #expect(brain.presentation.startedAt == started)

        brain.update(c, now: at(3.6 + PetBrain.strokeHold + 0.1))
        #expect(brain.presentation.animation == .leanRight)
    }

    @Test("a stroke is back and forth, not a single pass")
    func strokeDetector() {
        var detector = PetStrokeDetector()
        var t = t0
        var stroked = false
        func sweep(_ xs: StrideThrough<Double>) {
            for x in xs {
                t = t.addingTimeInterval(0.02)
                if detector.move(to: CGFloat(x), at: t) { stroked = true }
            }
        }
        sweep(stride(from: 0.0, through: 40, by: 2))
        #expect(!stroked)
        sweep(stride(from: 40.0, through: 20, by: -2))
        #expect(!stroked)
        sweep(stride(from: 20.0, through: 40, by: 2))
        #expect(stroked)
    }

    // MARK: - Focus

    @Test("a focus session is spent at the laptop and ends in a celebration")
    func focus() {
        var brain = PetBrain(now: t0)
        var c = PetContext()
        c.isFocusing = true
        brain.update(c, now: at(1))
        #expect(brain.presentation.mood == .focus)
        #expect([.codeType, .codeTypeBurst, .codeThink].contains(brain.presentation.animation))
        c.isFocusing = false
        brain.handle(.focusFinished, context: c, now: at(1500))
        #expect(brain.presentation.animation == .celebrate)
    }
}
