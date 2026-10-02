import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO's listening glow: shown only while NEO listens")
struct NeoListeningIndicatorTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func connected() -> NeoPresenceModel {
        var neo = NeoPresenceModel()
        neo.receive(.connected(true), at: t0)
        return neo
    }

    @Test("hidden until NEO listens; the glow with the word for the first 1.5 s, then the glow alone; gone the moment listening ends")
    func phases() {
        var mark = NeoListeningIndicator()
        #expect(mark.phase(at: t0) == .hidden && mark.since == nil && mark.nextWake(at: t0) == nil)

        let appeared = mark.update(listening: true, at: t0)
        #expect(appeared)
        #expect(mark.phase(at: t0) == .labelled)
        #expect(mark.phase(at: at(0.5)) == .labelled)
        #expect(mark.phase(at: at(1.49)) == .labelled)
        #expect(mark.phase(at: at(1.5)) == .glow)
        #expect(mark.phase(at: at(3)) == .glow)
        #expect(mark.phase(at: at(600)) == .glow) // however long NEO listens

        let left = mark.update(listening: false, at: at(4))
        #expect(left)
        #expect(mark.phase(at: at(4)) == .hidden && mark.since == nil)
    }

    @Test("the model says when the word steps aside — once, and never while hidden")
    func wake() {
        var mark = NeoListeningIndicator()
        mark.update(listening: true, at: t0)
        #expect(NeoListeningIndicator.labelDuration == 1.5)
        #expect(mark.nextWake(at: t0) == at(1.5))
        #expect(mark.nextWake(at: at(1)) == at(1.5))
        #expect(mark.nextWake(at: at(1.5)) == nil)
        #expect(mark.nextWake(at: at(9)) == nil)
        mark.update(listening: false, at: at(10))
        #expect(mark.nextWake(at: at(10)) == nil)
    }

    @Test("still listening keeps its start; only a new stretch of listening shows the word again")
    func stretches() {
        var mark = NeoListeningIndicator()
        mark.update(listening: true, at: t0)
        let again = mark.update(listening: true, at: at(2))
        #expect(!again && mark.since == t0 && mark.phase(at: at(2)) == .glow)
        let stillHidden = NeoListeningIndicator().since
        #expect(stillHidden == nil)

        mark.update(listening: false, at: at(3))
        let noChange = mark.update(listening: false, at: at(3.5))
        #expect(!noChange)
        mark.update(listening: true, at: at(5))
        #expect(mark.since == at(5) && mark.phase(at: at(5.2)) == .labelled)
    }

    @Test("it follows NEO's HELD state: listening shows it, every other state hides it")
    func followsPresence() {
        var neo = connected()
        var mark = NeoListeningIndicator()
        neo.receive(.state(.idle), at: t0)
        mark.update(presence: neo, at: t0)
        #expect(mark.phase(at: t0) == .hidden)

        neo.receive(.state(.listening), at: at(1))
        mark.update(presence: neo, at: at(1))
        #expect(mark.phase(at: at(1)) == .labelled)

        // The next state waits out the dwell (350 ms): the mark stays until
        // the held state really changes.
        neo.receive(.state(.thinking), at: at(1.1))
        mark.update(presence: neo, at: at(1.1))
        #expect(neo.state == .listening && mark.phase(at: at(1.1)) == .labelled)
        neo.tick(at: at(1.35))
        mark.update(presence: neo, at: at(1.35))
        #expect(neo.state == .thinking && mark.phase(at: at(1.35)) == .hidden)

        for state in NeoState.allCases where state != .listening {
            var other = connected()
            other.receive(.state(state), at: t0)
            var none = NeoListeningIndicator()
            none.update(presence: other, at: t0)
            #expect(none.phase(at: t0) == .hidden, "\(state)")
        }
    }

    @Test("NEO absent: no mark — a state from no core, and a core going away mid-listen")
    func absent() {
        var neo = NeoPresenceModel()
        var mark = NeoListeningIndicator()
        neo.receive(.state(.listening), at: t0) // not connected: a state from nowhere
        mark.update(presence: neo, at: t0)
        #expect(mark.phase(at: t0) == .hidden)
        #expect(mark.mark(for: .idle, at: t0, labelWidth: 50) == nil)

        neo = connected()
        neo.receive(.state(.listening), at: t0)
        mark.update(presence: neo, at: t0)
        #expect(mark.phase(at: at(0.2)) == .labelled)
        neo.receive(.connected(false), at: at(0.5))
        mark.update(presence: neo, at: at(0.5))
        #expect(mark.phase(at: at(0.5)) == .hidden)
        for state in IslandState.allCases {
            #expect(mark.mark(for: state, at: at(0.5), labelWidth: 50) == nil, "\(state)")
        }
    }

    @Test("its accessibility label names the fox")
    func accessibility() {
        #expect(NeoListeningIndicator.accessibilityLabel == "Neo is listening")
        #expect(NeoListeningIndicator.label == "Listening")
    }
}

@Suite("NEO's listening glow: its size, its breath, and the room its word takes")
struct NeoListeningLayoutTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 6_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    let geometry = NotchGeometry.make(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0))
    /// "Listening" in the compact font, as the app measures it.
    let word: CGFloat = 50

    private func listening() -> NeoListeningIndicator {
        var mark = NeoListeningIndicator()
        mark.update(listening: true, at: t0)
        return mark
    }

    /// Every shape the pet rides, with an island size it really takes.
    private let shapes: [(IslandState, CGSize)] = [
        (.idle, CGSize(width: 219, height: 32)), (.wings, CGSize(width: 360, height: 32)),
        (.compact, CGSize(width: 308, height: 32)), (.expanded, CGSize(width: 514, height: 88)),
        (.interactive, CGSize(width: 440, height: 300)), (.appPanel, CGSize(width: 440, height: 300)),
        (.meeting, CGSize(width: 360, height: 120)),
    ]

    @Test("the glow is the fox's size + 6 pt: 22 pt in the notch strip, 38 pt expanded, centred on the pet")
    func glowSize() {
        #expect(NeoListeningLayout.glowSpread == 3)
        #expect(NeoListeningLayout.glowDiameter(petSize: 16) == 22)
        #expect(NeoListeningLayout.glowDiameter(petSize: 32) == 38)
        for (state, size) in shapes {
            let pet = PetLayout.placement(for: state, islandSize: size, notchHeight: 32)!
            let glow = NeoListeningLayout.glowFrame(behind: pet)
            let petRect = CGRect(x: pet.origin.x, y: pet.origin.y, width: pet.size, height: pet.size)
            #expect(glow.width == pet.size + 6 && glow.height == pet.size + 6, "\(state)")
            #expect(glow.midX == petRect.midX && glow.midY == petRect.midY, "\(state)")
            #expect(glow.contains(petRect), "\(state)")
        }
    }

    @Test("at the top of a breath the glow is still inside the 32-pt notch strip, and inside the island in every shape")
    func glowStaysInside() {
        let top = NeoListeningLayout.glowScaleRange.upperBound
        #expect(NeoListeningLayout.glowDiameter(petSize: PetLayout.artSize) * top <= 32)
        for (state, size) in shapes {
            let pet = PetLayout.placement(for: state, islandSize: size, notchHeight: 32)!
            let glow = NeoListeningLayout.glowFrame(behind: pet, scale: top)
            #expect(CGRect(origin: .zero, size: size).contains(glow), "\(state)")
            if pet.scale == 1 {
                #expect(glow.minY >= 0 && glow.maxY <= 32, "\(state): within the notch strip")
            }
        }
        // On the idle dock, either side of the notch: clear of the notch too.
        let notch = geometry.notchFrame
        for side in [PetSide.right, .left] {
            var content = IslandContentSize.default
            content.petDock = PetDock(side: side, reach: PetLayout.idleDock)
            let island = geometry.frame(for: .idle, content: content)
            let pet = PetLayout.placement(for: .idle, islandSize: island.size, notchHeight: 32, dock: content.petDock!)!
            let glow = NeoListeningLayout.glowFrame(behind: pet, scale: top)
            #expect(CGRect(origin: .zero, size: island.size).contains(glow), "\(side)")
            #expect(!glow.intersects(CGRect(x: notch.minX - island.minX, y: 0, width: notch.width, height: 32)), "\(side)")
        }
    }

    @Test("the breath: opacity 0.35–0.75 and scale 0.92–1.06 on a 1.6 s cycle, eased at both ends, steady under Reduce Motion")
    func breath() {
        #expect(NeoListeningLayout.breathPeriod == 1.6)
        #expect(NeoListeningLayout.glowOpacityRange == 0.35...0.75)
        #expect(NeoListeningLayout.glowScaleRange == 0.92...1.06)
        // It starts half-way and rising, peaks 0.4 s in, bottoms out at 1.2 s.
        #expect(abs(NeoListeningLayout.breath(at: 0) - 0.5) < 1e-9)
        #expect(abs(NeoListeningLayout.breath(at: 0.4) - 1) < 1e-9)
        #expect(abs(NeoListeningLayout.breath(at: 1.2)) < 1e-9)
        #expect(NeoListeningLayout.breath(at: 0.2) > NeoListeningLayout.breath(at: 0))
        var low = 1.0, high = 0.0
        for step in 0...960 {
            let time = Double(step) / 60
            let breath = NeoListeningLayout.breath(at: time)
            #expect(breath >= -1e-9 && breath <= 1 + 1e-9)
            // One cycle later it is where it was: 1.6 s, exactly.
            #expect(abs(NeoListeningLayout.breath(at: time + 1.6) - breath) < 1e-9)
            let opacity = NeoListeningLayout.glowOpacity(breath: breath)
            let scale = NeoListeningLayout.glowScale(breath: breath)
            #expect(opacity >= 0.35 - 1e-9 && opacity <= 0.75 + 1e-9)
            #expect(scale >= 0.92 - 1e-9 && scale <= 1.06 + 1e-9)
            low = min(low, opacity); high = max(high, opacity)
        }
        #expect(abs(low - 0.35) < 1e-3 && abs(high - 0.75) < 1e-3, "it really travels the whole range")
        // Ease in and out: it moves slowest at the two ends, fastest between.
        let nearEnd = abs(NeoListeningLayout.breath(at: 0.45) - NeoListeningLayout.breath(at: 0.4))
        let midway = abs(NeoListeningLayout.breath(at: 0.85) - NeoListeningLayout.breath(at: 0.8))
        #expect(nearEnd < midway / 4)
        // The ends, and out-of-range input, are clamped.
        #expect(NeoListeningLayout.glowOpacity(breath: 0) == 0.35 && NeoListeningLayout.glowOpacity(breath: 1) == 0.75)
        #expect(NeoListeningLayout.glowOpacity(breath: 7) == 0.75 && NeoListeningLayout.glowOpacity(breath: -7) == 0.35)
        #expect(NeoListeningLayout.glowScale(breath: 0) == 0.92 && abs(NeoListeningLayout.glowScale(breath: 1) - 1.06) < 1e-9)
        // Deterministic: the same instant draws the same glow (no noise, no level input).
        #expect(NeoListeningLayout.breath(at: 1.25) == NeoListeningLayout.breath(at: 1.25))
        // Reduce Motion: a steady glow inside the breathing range, at its drawn size.
        #expect(NeoListeningLayout.glowOpacityRange.contains(NeoListeningLayout.steadyOpacity))
        #expect(NeoListeningLayout.steadyScale == 1)
    }

    @Test("the width math: only the word takes room — 56 pt with it, NOTHING for the glow")
    func slots() {
        #expect(NeoListeningLayout.slot(.hidden, labelWidth: word) == 0)
        #expect(NeoListeningLayout.slot(.glow, labelWidth: word) == 0)
        #expect(NeoListeningLayout.slot(.labelled, labelWidth: word) == 56) // 6 + 50
        #expect(NeoListeningLayout.maxSlot == 56)
        #expect(NeoListeningLayout.maxSlot == NeoListeningLayout.labelGap + NeoListeningLayout.maxLabelWidth)
        // The gap clears the halo's own reach past the pet.
        #expect(NeoListeningLayout.labelGap >= NeoListeningLayout.glowSpread)
        // A word wider than the cap never widens the island further; a
        // nonsense width takes no room at all.
        #expect(NeoListeningLayout.slot(.labelled, labelWidth: 400) == NeoListeningLayout.maxSlot)
        #expect(NeoListeningLayout.slot(.labelled, labelWidth: -5) == 0)
        #expect(NeoListeningLayout.slot(.labelled, labelWidth: 30) == 36)
    }

    @Test("the mark in each shape: the word and its room for 1.5 s where the shape grows, then zero width; the glow only in the fixed strips; nothing where the pet steps aside")
    func marks() {
        let indicator = listening()
        for state in [IslandState.idle, .wings, .compact, .expanded] {
            let early = indicator.mark(for: state, at: at(0.5), labelWidth: word)
            #expect(early == NeoListeningMark(showsLabel: true, labelWidth: 50, slot: 56, since: t0), "\(state)")
            let justBefore = indicator.mark(for: state, at: at(1.49), labelWidth: word)
            #expect(justBefore?.showsLabel == true && justBefore?.slot == 56, "\(state)")
            // The word gone: the glow is still there, and takes no room.
            for time in [1.5, 3.0, 600.0] {
                let later = indicator.mark(for: state, at: at(time), labelWidth: word)
                #expect(later == NeoListeningMark(showsLabel: false, labelWidth: 0, slot: 0, since: t0), "\(state) at \(time)")
            }
            // No measurable word: no word and no room, only the glow.
            let wordless = indicator.mark(for: state, at: at(0.5), labelWidth: 0)
            #expect(wordless == NeoListeningMark(showsLabel: false, labelWidth: 0, slot: 0, since: t0), "\(state)")
        }
        for state in [IslandState.interactive, .appPanel, .meeting] {
            for time in [0.5, 3.0] {
                let mark = indicator.mark(for: state, at: at(time), labelWidth: word)
                #expect(mark == NeoListeningMark(showsLabel: false, labelWidth: 0, slot: 0, since: t0), "\(state)")
            }
        }
        // Exactly where the pet has no placement, the mark has none either.
        for state in IslandState.allCases {
            let pet = PetLayout.placement(for: state, islandSize: CGSize(width: 440, height: 300), notchHeight: 32)
            #expect((NeoListeningLayout.room(in: state) == nil) == (pet == nil), "\(state)")
            #expect((indicator.mark(for: state, at: at(0.5), labelWidth: word) == nil) == (pet == nil), "\(state)")
        }
    }

    @Test("on the idle dock the glow waits for the pet to stand at its spot")
    func petAway() {
        let indicator = listening()
        #expect(indicator.mark(for: .idle, at: at(0.5), labelWidth: word, petAtHome: false) == nil)
        #expect(indicator.mark(for: .idle, at: at(3), labelWidth: word, petAtHome: false) == nil)
        #expect(indicator.mark(for: .idle, at: at(0.5), labelWidth: word, petAtHome: true) != nil)
        // Elsewhere the pet is always at its place in the bar.
        #expect(indicator.mark(for: .compact, at: at(0.5), labelWidth: word, petAtHome: false) != nil)
    }

    @Test("NEO idle or absent: every shape is exactly today's island")
    func untouched() {
        var content = IslandContentSize.default
        #expect(content.listeningSlot == 0)
        content.petDock = .home
        let today = geometry.compactBar(lead: 0, trail: PetLayout.idleDock)
        #expect(geometry.frame(for: .idle, content: content) == today)
        // A hidden mark reserves nothing, so the frame cannot differ.
        let hidden = NeoListeningIndicator().mark(for: .idle, at: t0, labelWidth: word)
        #expect(hidden == nil)
        content.listeningSlot = hidden?.slot ?? 0
        #expect(geometry.frame(for: .idle, content: content) == today)
        // Without a dock (no pet, or the pet inside the notch) idle is the
        // notch whatever the slot says.
        var bare = IslandContentSize.default
        bare.listeningSlot = 56
        #expect(geometry.frame(for: .idle, content: bare) == geometry.notchFrame)
        bare.petDock = PetDock(side: .right, reach: 0)
        #expect(geometry.frame(for: .idle, content: bare) == geometry.notchFrame)
    }

    @Test("zero width after the word: 1.5 s into listening every shape has exactly the frame it has without NEO")
    func noWidthForTheGlow() {
        let indicator = listening()
        for state in IslandState.allCases {
            var plain = IslandContentSize.default
            if state == .idle { plain.petDock = .home }
            var lit = plain
            lit.listeningSlot = indicator.mark(for: state, at: at(3), labelWidth: word)?.slot ?? 0
            #expect(lit == plain, "\(state)")
            #expect(geometry.frame(for: state, content: lit) == geometry.frame(for: state, content: plain), "\(state)")
        }
        // …and on the left of the notch.
        var left = IslandContentSize.default
        left.petDock = PetDock(side: .left, reach: PetLayout.idleDock)
        let plain = geometry.frame(for: .idle, content: left)
        left.listeningSlot = indicator.mark(for: .idle, at: at(1.5), labelWidth: word)!.slot
        #expect(geometry.frame(for: .idle, content: left) == plain)
    }

    @Test("for the word's 1.5 s the idle dock grows by 56 pt on the pet's side only — the notch side never moves")
    func idleGrowth() {
        var content = IslandContentSize.default
        content.petDock = .home
        let plain = geometry.frame(for: .idle, content: content)

        content.listeningSlot = listening().mark(for: .idle, at: at(0.5), labelWidth: word)!.slot
        let labelled = geometry.frame(for: .idle, content: content)
        #expect(labelled.minX == plain.minX && labelled.maxX == plain.maxX + 56)
        #expect(labelled.height == plain.height && labelled.minY == plain.minY)

        // The pet on the left of the notch: the island grows LEFT, and its
        // right edge stays the notch's.
        var left = IslandContentSize.default
        left.petDock = PetDock(side: .left, reach: PetLayout.idleDock)
        let leftPlain = geometry.frame(for: .idle, content: left)
        left.listeningSlot = 56
        let leftLabelled = geometry.frame(for: .idle, content: left)
        #expect(leftLabelled.maxX == leftPlain.maxX && leftLabelled.minX == leftPlain.minX - 56)

        // Only idle reads the slot: the wings and the compact bar carry it in
        // their measured widths.
        var other = IslandContentSize.default
        other.listeningSlot = 56
        for state in IslandState.allCases where state != .idle {
            #expect(geometry.frame(for: state, content: other) == geometry.frame(for: state, content: .default), "\(state)")
        }
    }

    @Test("the word stands between the notch and the pet — never under the notch, never on the pet — on either side")
    func besideThePet() {
        let indicator = listening()
        let notch = geometry.notchFrame
        for side in [PetSide.right, .left] {
            let mark = indicator.mark(for: .idle, at: at(0.5), labelWidth: word)!
            var content = IslandContentSize.default
            content.petDock = PetDock(side: side, reach: PetLayout.idleDock)
            content.listeningSlot = mark.slot
            let island = geometry.frame(for: .idle, content: content)
            let pet = PetLayout.placement(for: .idle, islandSize: island.size, notchHeight: 32, dock: content.petDock!)!
            let rect = NeoListeningLayout.labelFrame(mark, beside: pet)
            let petRect = CGRect(x: pet.origin.x, y: pet.origin.y, width: pet.size, height: pet.size)
            // The notch, in the island's coordinates.
            let notchMinX = notch.minX - island.minX
            let notchMaxX = notch.maxX - island.minX
            #expect(rect.width == 50 && rect.height == NeoListeningLayout.labelHeight)
            #expect(rect.minY >= 0 && rect.maxY <= 32)
            #expect(rect.midY == petRect.midY)
            if side == .right {
                #expect(rect.minX == notchMaxX + PetLayout.dockInset, "the notch's edge, the dock's inset, then the word")
                #expect(rect.maxX == petRect.minX - NeoListeningLayout.labelGap)
                #expect(petRect.maxX == island.width - PetLayout.dockInset, "the pet keeps its inset from the outer edge")
            } else {
                #expect(rect.maxX == notchMinX - PetLayout.dockInset)
                #expect(rect.minX == petRect.maxX + NeoListeningLayout.labelGap)
                #expect(petRect.minX == PetLayout.dockInset)
            }
            #expect(!rect.intersects(CGRect(x: notchMinX, y: 0, width: notch.width, height: 32)))
            #expect(!rect.intersects(petRect))
            // The word is clear of the halo too, even at the top of a breath.
            #expect(!rect.intersects(NeoListeningLayout.glowFrame(behind: pet, scale: NeoListeningLayout.glowScaleRange.upperBound)))

            // Without its word the mark has no rectangle beside the pet at all.
            let later = indicator.mark(for: .idle, at: at(3), labelWidth: word)!
            #expect(NeoListeningLayout.labelFrame(later, beside: pet).width == 0)
        }
    }

    @Test("in a bar and in the expanded island the word sits left of the pet, inside the room the content gave up")
    func besideThePetInABar() {
        let indicator = listening()
        let mark = indicator.mark(for: .compact, at: at(0.5), labelWidth: word)!
        let size = CGSize(width: 380, height: 32)
        let pet = PetLayout.placement(for: .compact, islandSize: size, notchHeight: 32)!
        let rect = NeoListeningLayout.labelFrame(mark, beside: pet)
        #expect(rect.maxX == pet.origin.x - NeoListeningLayout.labelGap)
        // The content's trailing edge: the bar's inset, the pet's slot, the word's slot.
        let contentMaxX = size.width - DesignTokens.compactInset - PetLayout.barSlot - mark.slot
        #expect(rect.minX >= contentMaxX)

        let expanded = CGSize(width: 514, height: 88)
        let big = PetLayout.placement(for: .expanded, islandSize: expanded, notchHeight: 32)!
        let early = indicator.mark(for: .expanded, at: at(0.5), labelWidth: word)!
        let bigRect = NeoListeningLayout.labelFrame(early, beside: big)
        #expect(bigRect.maxX == big.origin.x - NeoListeningLayout.labelGap)
        #expect(bigRect.midY == big.origin.y + big.size / 2)
        #expect(bigRect.minY >= 32, "below the notch strip, with the larger pet")
        // The larger pet's glow stays below the notch strip as well.
        #expect(NeoListeningLayout.glowFrame(behind: big, scale: NeoListeningLayout.glowScaleRange.upperBound).minY >= 32)
    }

    @Test("Ghost Mode hides the glow with the island: it adds no shape of its own")
    func ghost() {
        for state in IslandState.allCases where NeoListeningLayout.room(in: state) != nil {
            #expect(GhostMode.hidesFromCapture(state: state, ghostModeEnabled: true), "\(state)")
            #expect(!GhostMode.alwaysPrivate.contains(state), "\(state)")
        }
    }
}
