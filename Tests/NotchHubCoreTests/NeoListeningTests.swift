import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO's listening mark: shown only while NEO listens")
struct NeoListeningIndicatorTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func connected() -> NeoPresenceModel {
        var neo = NeoPresenceModel()
        neo.receive(.connected(true), at: t0)
        return neo
    }

    @Test("hidden until NEO listens; the word for the first 1.5 s, then the bars alone; gone the moment listening ends")
    func phases() {
        var mark = NeoListeningIndicator()
        #expect(mark.phase(at: t0) == .hidden && mark.since == nil && mark.nextWake(at: t0) == nil)

        let appeared = mark.update(listening: true, at: t0)
        #expect(appeared)
        #expect(mark.phase(at: t0) == .labelled)
        #expect(mark.phase(at: at(0.5)) == .labelled)
        #expect(mark.phase(at: at(1.49)) == .labelled)
        #expect(mark.phase(at: at(1.5)) == .bars)
        #expect(mark.phase(at: at(3)) == .bars)
        #expect(mark.phase(at: at(600)) == .bars) // however long NEO listens

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
        #expect(!again && mark.since == t0 && mark.phase(at: at(2)) == .bars)
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

@Suite("NEO's listening mark: its size and the room it takes")
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

    @Test("four thin bars: 14 pt wide, at most 12 pt tall")
    func bars() {
        #expect(NeoListeningLayout.barCount == 4)
        #expect(NeoListeningLayout.markWidth == 14)
        #expect(NeoListeningLayout.markWidth >= 12 && NeoListeningLayout.markWidth <= 14)
        #expect(NeoListeningLayout.markHeight <= 12)
        #expect(NeoListeningLayout.barWidth <= 2)
    }

    @Test("the width math: nothing hidden, 18 pt for the bars, at most 72 pt with the word")
    func slots() {
        #expect(NeoListeningLayout.slot(.hidden, labelWidth: word) == 0)
        #expect(NeoListeningLayout.slot(.bars, labelWidth: word) == 18)
        #expect(NeoListeningLayout.barsSlot == NeoListeningLayout.markWidth + NeoListeningLayout.gap)
        #expect(NeoListeningLayout.slot(.labelled, labelWidth: word) == 72) // 18 + 4 + 50
        #expect(NeoListeningLayout.maxSlot == 72)
        // A word wider than the cap never widens the island further; a
        // nonsense width never shrinks it below the bars.
        #expect(NeoListeningLayout.slot(.labelled, labelWidth: 400) == NeoListeningLayout.maxSlot)
        #expect(NeoListeningLayout.slot(.labelled, labelWidth: -5) == 22) // 18 + 4: the gap, no word
        #expect(NeoListeningLayout.slot(.labelled, labelWidth: 30) == 52)
    }

    @Test("the mark in each shape: the word and its room where the shape grows, the bars alone in the panels' notch strip, nothing where the pet steps aside")
    func marks() {
        let indicator = listening()
        for state in [IslandState.idle, .wings, .compact, .expanded] {
            let early = indicator.mark(for: state, at: at(0.5), labelWidth: word)
            #expect(early == NeoListeningMark(showsLabel: true, labelWidth: 50, slot: 72, since: t0), "\(state)")
            #expect(early?.width == 68)
            let later = indicator.mark(for: state, at: at(3), labelWidth: word)
            #expect(later == NeoListeningMark(showsLabel: false, labelWidth: 0, slot: 18, since: t0), "\(state)")
            #expect(later?.width == 14)
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

    @Test("on the idle dock the mark waits for the pet to stand at its spot")
    func petAway() {
        let indicator = listening()
        #expect(indicator.mark(for: .idle, at: at(0.5), labelWidth: word, petAtHome: false) == nil)
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
        content.listeningSlot = hidden?.slot ?? 0
        #expect(geometry.frame(for: .idle, content: content) == today)
        // Without a dock (no pet, or the pet inside the notch) idle is the
        // notch whatever the slot says.
        var bare = IslandContentSize.default
        bare.listeningSlot = 72
        #expect(geometry.frame(for: .idle, content: bare) == geometry.notchFrame)
        bare.petDock = PetDock(side: .right, reach: 0)
        #expect(geometry.frame(for: .idle, content: bare) == geometry.notchFrame)
    }

    @Test("the idle dock grows on the pet's side only: 72 pt with the word, 18 pt after — the notch side never moves")
    func idleGrowth() {
        var content = IslandContentSize.default
        content.petDock = .home
        let plain = geometry.frame(for: .idle, content: content)

        content.listeningSlot = 72
        let labelled = geometry.frame(for: .idle, content: content)
        #expect(labelled.minX == plain.minX && labelled.maxX == plain.maxX + 72)
        #expect(labelled.height == plain.height && labelled.minY == plain.minY)

        content.listeningSlot = 18
        let bars = geometry.frame(for: .idle, content: content)
        #expect(bars.minX == plain.minX && bars.maxX == plain.maxX + 18)

        // The pet on the left of the notch: the island grows LEFT, and its
        // right edge stays the notch's.
        var left = IslandContentSize.default
        left.petDock = PetDock(side: .left, reach: PetLayout.idleDock)
        let leftPlain = geometry.frame(for: .idle, content: left)
        left.listeningSlot = 72
        let leftLabelled = geometry.frame(for: .idle, content: left)
        #expect(leftLabelled.maxX == leftPlain.maxX && leftLabelled.minX == leftPlain.minX - 72)

        // Only idle reads the slot: the bars carry it in their measured widths.
        var other = IslandContentSize.default
        other.listeningSlot = 72
        for state in IslandState.allCases where state != .idle {
            #expect(geometry.frame(for: state, content: other) == geometry.frame(for: state, content: .default), "\(state)")
        }
    }

    @Test("the mark stands between the notch and the pet — never under the notch, never on the pet — on either side")
    func besideThePet() {
        let indicator = listening()
        let notch = geometry.notchFrame
        for side in [PetSide.right, .left] {
            for time in [0.5, 3.0] {
                let mark = indicator.mark(for: .idle, at: at(time), labelWidth: word)!
                var content = IslandContentSize.default
                content.petDock = PetDock(side: side, reach: PetLayout.idleDock)
                content.listeningSlot = mark.slot
                let island = geometry.frame(for: .idle, content: content)
                let pet = PetLayout.placement(for: .idle, islandSize: island.size, notchHeight: 32, dock: content.petDock!)!
                let rect = NeoListeningLayout.frame(mark, beside: pet)
                let petRect = CGRect(x: pet.origin.x, y: pet.origin.y, width: pet.size, height: pet.size)
                // The notch, in the island's coordinates.
                let notchMinX = notch.minX - island.minX
                let notchMaxX = notch.maxX - island.minX
                #expect(rect.width == mark.width && rect.height == NeoListeningLayout.markHeight)
                #expect(rect.minY >= 0 && rect.maxY <= 32)
                #expect(rect.midY == petRect.midY)
                if side == .right {
                    #expect(rect.minX == notchMaxX + PetLayout.dockInset, "the notch's edge, the dock's inset, then the mark")
                    #expect(rect.maxX == petRect.minX - NeoListeningLayout.gap)
                    #expect(petRect.maxX == island.width - PetLayout.dockInset, "the pet keeps its inset from the outer edge")
                } else {
                    #expect(rect.maxX == notchMinX - PetLayout.dockInset)
                    #expect(rect.minX == petRect.maxX + NeoListeningLayout.gap)
                    #expect(petRect.minX == PetLayout.dockInset)
                }
                #expect(!rect.intersects(CGRect(x: notchMinX, y: 0, width: notch.width, height: 32)))
                #expect(!rect.intersects(petRect))
            }
        }
    }

    @Test("in a bar and in the expanded island the mark sits left of the pet, inside the room the content gave up")
    func besideThePetInABar() {
        let indicator = listening()
        let mark = indicator.mark(for: .compact, at: at(0.5), labelWidth: word)!
        let size = CGSize(width: 380, height: 32)
        let pet = PetLayout.placement(for: .compact, islandSize: size, notchHeight: 32)!
        let rect = NeoListeningLayout.frame(mark, beside: pet)
        #expect(rect.maxX == pet.origin.x - NeoListeningLayout.gap)
        // The content's trailing edge: the bar's inset, the pet's slot, the mark's slot.
        let contentMaxX = size.width - DesignTokens.compactInset - PetLayout.barSlot - mark.slot
        #expect(rect.minX >= contentMaxX)

        let expanded = CGSize(width: 514, height: 88)
        let big = PetLayout.placement(for: .expanded, islandSize: expanded, notchHeight: 32)!
        let later = indicator.mark(for: .expanded, at: at(3), labelWidth: word)!
        let bigRect = NeoListeningLayout.frame(later, beside: big)
        #expect(bigRect.maxX == big.origin.x - NeoListeningLayout.gap)
        #expect(bigRect.midY == big.origin.y + big.size / 2)
        #expect(bigRect.minY >= 32, "below the notch strip, with the larger pet")
    }

    @Test("the bars move procedurally: always between a dot and full height, out of step with each other, and still under Reduce Motion")
    func motion() {
        var seen: [Set<Int>] = Array(repeating: [], count: NeoListeningLayout.barCount)
        for step in 0..<600 {
            let time = Double(step) / 30
            for bar in 0..<NeoListeningLayout.barCount {
                let level = NeoListeningLayout.level(bar: bar, at: time)
                #expect(level >= NeoListeningLayout.minLevel && level <= 1)
                let height = NeoListeningLayout.barHeight(level: level)
                #expect(height >= NeoListeningLayout.minBarHeight && height <= NeoListeningLayout.markHeight)
                seen[bar].insert(Int(height * 2))
            }
        }
        // Each bar really travels, and the four are not one bar drawn four times.
        for bar in 0..<NeoListeningLayout.barCount {
            #expect(seen[bar].count >= 10, "bar \(bar)")
        }
        let together = (0..<NeoListeningLayout.barCount).map { NeoListeningLayout.level(bar: $0, at: 0.7) }
        #expect(Set(together.map { Int($0 * 100) }).count > 1)
        // Deterministic: the same instant draws the same bars (no noise, no level input).
        #expect(NeoListeningLayout.level(bar: 2, at: 1.25) == NeoListeningLayout.level(bar: 2, at: 1.25))

        #expect(NeoListeningLayout.restingLevels.count == NeoListeningLayout.barCount)
        for level in NeoListeningLayout.restingLevels {
            let height = NeoListeningLayout.barHeight(level: level)
            #expect(height >= NeoListeningLayout.minBarHeight && height <= NeoListeningLayout.markHeight)
        }
        #expect(NeoListeningLayout.barHeight(level: 0) == NeoListeningLayout.minBarHeight)
        #expect(NeoListeningLayout.barHeight(level: 7) == NeoListeningLayout.markHeight)
    }

    @Test("Ghost Mode hides the mark with the island: it adds no shape of its own")
    func ghost() {
        for state in IslandState.allCases where NeoListeningLayout.room(in: state) != nil {
            #expect(GhostMode.hidesFromCapture(state: state, ghostModeEnabled: true), "\(state)")
            #expect(!GhostMode.alwaysPrivate.contains(state), "\(state)")
        }
    }
}
