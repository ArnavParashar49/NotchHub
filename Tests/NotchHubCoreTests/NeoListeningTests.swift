import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO's listening glow: one pulse each time NEO starts to listen")
struct NeoListeningIndicatorTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func connected() -> NeoPresenceModel {
        var neo = NeoPresenceModel()
        neo.receive(.connected(true), at: t0)
        return neo
    }

    @Test("the pulse window: nothing until NEO listens, the glow for 1.4 s from the moment it does, then nothing — however long NEO listens")
    func pulseWindow() {
        var indicator = NeoListeningIndicator()
        #expect(NeoListeningIndicator.pulseDuration == 1.4)
        #expect(indicator.since == nil && indicator.pulseStart == nil)
        #expect(!indicator.isPulsing(at: t0) && indicator.mark(for: .idle, at: t0) == nil && indicator.nextWake(at: t0) == nil)

        let began = indicator.update(listening: true, at: t0)
        #expect(began && indicator.since == t0 && indicator.pulseStart == t0)
        for time in [0, 0.2, 0.45, 1.0, 1.39] {
            #expect(indicator.isPulsing(at: at(time)), "\(time)")
            #expect(indicator.mark(for: .idle, at: at(time)) == NeoListeningMark(pulseStart: t0), "\(time)")
        }
        // The pulse over: nil, for the rest of the stretch.
        for time in [1.4, 1.5, 3, 60, 600] {
            #expect(!indicator.isPulsing(at: at(time)), "\(time)")
            #expect(indicator.mark(for: .idle, at: at(time)) == nil, "\(time)")
        }
        // NEO is still listening all the while: the stretch goes on, dark.
        #expect(indicator.since == t0)

        let left = indicator.update(listening: false, at: at(700))
        #expect(left && indicator.since == nil && indicator.pulseStart == nil)
        #expect(indicator.mark(for: .idle, at: at(700)) == nil)
    }

    @Test("the model says when the pulse ends — once, and never while dark")
    func wake() {
        var indicator = NeoListeningIndicator()
        indicator.update(listening: true, at: t0)
        #expect(indicator.nextWake(at: t0) == at(1.4))
        #expect(indicator.nextWake(at: at(1)) == at(1.4))
        #expect(indicator.nextWake(at: at(1.4)) == nil)
        #expect(indicator.nextWake(at: at(9)) == nil)
        indicator.update(listening: false, at: at(10))
        #expect(indicator.nextWake(at: at(10)) == nil)
    }

    @Test("once per stretch: still listening never pulses again; listening that left and came back does")
    func stretches() {
        var indicator = NeoListeningIndicator()
        indicator.update(listening: true, at: t0)
        // Fed the same state again — mid-pulse, and long after it.
        let midPulse = indicator.update(listening: true, at: at(0.6))
        #expect(!midPulse && indicator.pulseStart == t0)
        let after = indicator.update(listening: true, at: at(2))
        #expect(!after && indicator.since == t0 && indicator.pulseStart == t0)
        #expect(indicator.mark(for: .idle, at: at(2)) == nil && indicator.mark(for: .idle, at: at(2.3)) == nil)
        #expect(indicator.nextWake(at: at(2)) == nil)

        indicator.update(listening: false, at: at(3))
        let noChange = indicator.update(listening: false, at: at(3.5))
        #expect(!noChange)

        // A new stretch: a new pulse, from its own start.
        let again = indicator.update(listening: true, at: at(5))
        #expect(again && indicator.since == at(5) && indicator.pulseStart == at(5))
        #expect(indicator.mark(for: .idle, at: at(5.45)) == NeoListeningMark(pulseStart: at(5)))
        #expect(indicator.nextWake(at: at(5.45)) == at(6.4))
        #expect(indicator.mark(for: .idle, at: at(6.4)) == nil)
    }

    @Test("listening ends mid-pulse: the mark goes at once (the view finishes the fade), and nothing is left to wake for")
    func cutShort() {
        var indicator = NeoListeningIndicator()
        indicator.update(listening: true, at: t0)
        #expect(indicator.mark(for: .idle, at: at(0.5)) != nil)
        let left = indicator.update(listening: false, at: at(0.6))
        #expect(left)
        #expect(indicator.mark(for: .idle, at: at(0.6)) == nil && !indicator.isPulsing(at: at(0.6)))
        #expect(indicator.nextWake(at: at(0.6)) == nil)
        // Back within what would have been the first pulse: a pulse of its own.
        indicator.update(listening: true, at: at(0.9))
        #expect(indicator.mark(for: .idle, at: at(1.0)) == NeoListeningMark(pulseStart: at(0.9)))
        #expect(indicator.mark(for: .idle, at: at(2.29)) != nil && indicator.mark(for: .idle, at: at(2.3)) == nil)
    }

    @Test("it follows NEO's HELD state: listening pulses, every other state shows nothing")
    func followsPresence() {
        var neo = connected()
        var indicator = NeoListeningIndicator()
        neo.receive(.state(.idle), at: t0)
        indicator.update(presence: neo, at: t0)
        #expect(indicator.mark(for: .idle, at: t0) == nil)

        neo.receive(.state(.listening), at: at(1))
        indicator.update(presence: neo, at: at(1))
        #expect(indicator.mark(for: .idle, at: at(1.05)) == NeoListeningMark(pulseStart: at(1)))

        // The next state waits out the dwell (350 ms): the pulse runs on
        // until the held state really changes.
        neo.receive(.state(.thinking), at: at(1.1))
        indicator.update(presence: neo, at: at(1.1))
        #expect(neo.state == .listening && indicator.mark(for: .idle, at: at(1.1)) != nil)
        neo.tick(at: at(1.35))
        indicator.update(presence: neo, at: at(1.35))
        #expect(neo.state == .thinking && indicator.mark(for: .idle, at: at(1.35)) == nil)

        for state in NeoState.allCases where state != .listening {
            var other = connected()
            other.receive(.state(state), at: t0)
            var none = NeoListeningIndicator()
            none.update(presence: other, at: t0)
            #expect(none.since == nil && none.mark(for: .idle, at: at(0.2)) == nil, "\(state)")
        }
    }

    @Test("NEO absent: no mark — a state from no core, and a core going away mid-pulse")
    func absent() {
        var neo = NeoPresenceModel()
        var indicator = NeoListeningIndicator()
        neo.receive(.state(.listening), at: t0) // not connected: a state from nowhere
        indicator.update(presence: neo, at: t0)
        #expect(indicator.since == nil && indicator.pulseStart == nil)
        for state in IslandState.allCases {
            #expect(indicator.mark(for: state, at: at(0.2)) == nil, "\(state)")
        }

        neo = connected()
        neo.receive(.state(.listening), at: t0)
        indicator.update(presence: neo, at: t0)
        #expect(indicator.mark(for: .idle, at: at(0.2)) != nil)
        neo.receive(.connected(false), at: at(0.5))
        indicator.update(presence: neo, at: at(0.5))
        #expect(indicator.since == nil && indicator.nextWake(at: at(0.5)) == nil)
        for state in IslandState.allCases {
            #expect(indicator.mark(for: state, at: at(0.5)) == nil, "\(state)")
        }
    }

    @Test("on the idle dock the pulse waits for the pet to stand at its spot — and still happens once")
    func waitsForThePet() {
        var indicator = NeoListeningIndicator()
        // Listening starts with the pet mid-game: the stretch runs, the pulse waits.
        let began = indicator.update(listening: true, at: t0, petInPlace: false)
        #expect(began && indicator.since == t0 && indicator.pulseStart == nil)
        #expect(indicator.mark(for: .idle, at: at(0.3)) == nil && indicator.nextWake(at: at(0.3)) == nil)
        let stillAway = indicator.update(listening: true, at: at(1), petInPlace: false)
        #expect(!stillAway && indicator.pulseStart == nil)

        // The pet comes home 2 s in: the whole pulse runs from there.
        let lit = indicator.update(listening: true, at: at(2), petInPlace: true)
        #expect(lit && indicator.since == t0 && indicator.pulseStart == at(2))
        #expect(indicator.mark(for: .idle, at: at(2.45)) == NeoListeningMark(pulseStart: at(2)))
        #expect(indicator.nextWake(at: at(2.45)) == at(3.4))
        #expect(indicator.mark(for: .idle, at: at(3.4)) == nil)

        // The pet leaving and coming home again in the same stretch: no second pulse.
        indicator.update(listening: true, at: at(4), petInPlace: false)
        let homeAgain = indicator.update(listening: true, at: at(5), petInPlace: true)
        #expect(!homeAgain && indicator.pulseStart == at(2))
        #expect(indicator.mark(for: .idle, at: at(5.2)) == nil)

        // A pet that steps off its spot mid-pulse is not lit where it is not.
        var other = NeoListeningIndicator()
        other.update(listening: true, at: t0)
        #expect(other.mark(for: .idle, at: at(0.5), petAtHome: false) == nil)
        #expect(other.mark(for: .idle, at: at(0.5), petAtHome: true) != nil)
        // Elsewhere the pet is always at its place in the bar.
        #expect(other.mark(for: .compact, at: at(0.5), petAtHome: false) != nil)
    }

    @Test("its accessibility label names the fox")
    func accessibility() {
        #expect(NeoListeningIndicator.accessibilityLabel == "Neo is listening")
    }
}

@Suite("NEO's listening glow: its size, its pulse, and the room it never takes")
struct NeoListeningLayoutTests {

    let t0 = Date(timeIntervalSinceReferenceDate: 6_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    let geometry = NotchGeometry.make(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0))

    private func listening() -> NeoListeningIndicator {
        var indicator = NeoListeningIndicator()
        indicator.update(listening: true, at: t0)
        return indicator
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

    @Test("at the peak of the pulse the glow is still inside the 32-pt notch strip, and inside the island in every shape")
    func glowStaysInside() {
        let top = NeoListeningLayout.pulseScaleRange.upperBound
        #expect(NeoListeningLayout.glowDiameter(petSize: PetLayout.artSize) * top <= 32)
        for (state, size) in shapes {
            let pet = PetLayout.placement(for: state, islandSize: size, notchHeight: 32)!
            let glow = NeoListeningLayout.glowFrame(behind: pet, scale: top)
            #expect(CGRect(origin: .zero, size: size).contains(glow), "\(state)")
            if pet.scale == 1 {
                #expect(glow.minY >= 0 && glow.maxY <= 32, "\(state): within the notch strip")
            } else {
                #expect(glow.minY >= 32, "\(state): the larger pet's glow stays below the notch strip")
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

    @Test("the pulse: 0 → 1 → 0 over 1.4 s — an eased rise to the peak at 0.45 s, a slower eased fall, and nothing before or after")
    func pulseCurve() {
        #expect(NeoListeningLayout.pulseDuration == 1.4 && NeoListeningLayout.pulseDuration == NeoListeningIndicator.pulseDuration)
        #expect(NeoListeningLayout.pulseRise == 0.45)
        #expect(abs(NeoListeningLayout.pulseFall - 0.95) < 1e-9)
        #expect(NeoListeningLayout.pulseFall > NeoListeningLayout.pulseRise, "the fade is slower than the swell")

        // Dark at both ends, the peak at 0.45 s.
        #expect(NeoListeningLayout.pulse(at: 0) == 0)
        #expect(abs(NeoListeningLayout.pulse(at: 0.45) - 1) < 1e-9)
        #expect(NeoListeningLayout.pulse(at: 1.4) == 0)
        // Half-way up the rise and half-way down the fall it is at half.
        #expect(abs(NeoListeningLayout.pulse(at: 0.225) - 0.5) < 1e-9)
        #expect(abs(NeoListeningLayout.pulse(at: 0.45 + 0.475) - 0.5) < 1e-9)
        // The snapshot's "fading" moment: well past the peak, still alight.
        #expect(abs(NeoListeningLayout.pulse(at: 1.0) - (0.5 + 0.5 * cos(.pi * 0.55 / 0.95))) < 1e-9)
        #expect(NeoListeningLayout.pulse(at: 1.0) > 0.3 && NeoListeningLayout.pulse(at: 1.0) < 0.45)

        // Nothing before the pulse or after it — it happens once, and never repeats.
        for time in [-5, -0.01, 1.4, 1.41, 1.85, 2.8, 3, 60, 3_600] {
            #expect(NeoListeningLayout.pulse(at: time) == 0, "\(time)")
        }

        // One hump: strictly up to the peak, strictly down from it, always in 0…1.
        var previous = 0.0
        var peak = 0.0
        for step in 1...140 {
            let time = Double(step) / 100
            let value = NeoListeningLayout.pulse(at: time)
            #expect(value >= 0 && value <= 1, "\(time)")
            if time <= 0.45 {
                #expect(value > previous, "rising at \(time)")
            } else {
                #expect(value < previous, "falling at \(time)")
            }
            previous = value
            peak = max(peak, value)
        }
        #expect(abs(peak - 1) < 1e-9)

        // Eased at every end: it leaves the dark, crests and lands slowly,
        // and moves fastest in between.
        let leaving = NeoListeningLayout.pulse(at: 0.02) - NeoListeningLayout.pulse(at: 0)
        let climbing = NeoListeningLayout.pulse(at: 0.235) - NeoListeningLayout.pulse(at: 0.215)
        let cresting = NeoListeningLayout.pulse(at: 0.45) - NeoListeningLayout.pulse(at: 0.43)
        let falling = NeoListeningLayout.pulse(at: 0.915) - NeoListeningLayout.pulse(at: 0.935)
        let landing = NeoListeningLayout.pulse(at: 1.38) - NeoListeningLayout.pulse(at: 1.4)
        #expect(leaving < climbing / 4 && cresting < climbing / 4)
        #expect(landing < falling / 4)
        #expect(falling < climbing, "the fall is the gentler slope")

        // Deterministic: the same instant draws the same glow (no noise, no level input).
        #expect(NeoListeningLayout.pulse(at: 0.8) == NeoListeningLayout.pulse(at: 0.8))
    }

    @Test("what the pulse draws: opacity 0 → 0.8 → 0 and scale 0.88 → 1.06 → 0.88; Reduce Motion fades softly at a fixed scale")
    func pulseDrawing() {
        #expect(NeoListeningLayout.peakOpacity == 0.8)
        #expect(NeoListeningLayout.pulseScaleRange == 0.88...1.06)
        #expect(NeoListeningLayout.glowOpacity(pulse: 0) == 0)
        #expect(abs(NeoListeningLayout.glowOpacity(pulse: 1) - 0.8) < 1e-9)
        #expect(abs(NeoListeningLayout.glowOpacity(pulse: 0.5) - 0.4) < 1e-9)
        #expect(abs(NeoListeningLayout.glowScale(pulse: 0) - 0.88) < 1e-9)
        #expect(abs(NeoListeningLayout.glowScale(pulse: 1) - 1.06) < 1e-9)
        // Out-of-range input is clamped.
        #expect(NeoListeningLayout.glowOpacity(pulse: 7) == NeoListeningLayout.glowOpacity(pulse: 1))
        #expect(NeoListeningLayout.glowOpacity(pulse: -7) == 0)
        #expect(NeoListeningLayout.glowScale(pulse: 7) == NeoListeningLayout.glowScale(pulse: 1))
        #expect(NeoListeningLayout.glowScale(pulse: -7) == NeoListeningLayout.glowScale(pulse: 0))

        // Over the whole pulse: fully dark at both ends, and after it.
        #expect(NeoListeningLayout.glowOpacity(pulse: NeoListeningLayout.pulse(at: 0)) == 0)
        #expect(abs(NeoListeningLayout.glowOpacity(pulse: NeoListeningLayout.pulse(at: 0.45)) - 0.8) < 1e-9)
        #expect(NeoListeningLayout.glowOpacity(pulse: NeoListeningLayout.pulse(at: 1.4)) == 0)
        #expect(NeoListeningLayout.glowOpacity(pulse: NeoListeningLayout.pulse(at: 3)) == 0)

        // Reduce Motion: one soft fade in and out, no swelling.
        #expect(NeoListeningLayout.reducedMotionScale == 1)
        #expect(NeoListeningLayout.reducedMotionPeakOpacity > 0 && NeoListeningLayout.reducedMotionPeakOpacity < NeoListeningLayout.peakOpacity)
        for step in 0...140 {
            let pulse = NeoListeningLayout.pulse(at: Double(step) / 100)
            #expect(NeoListeningLayout.glowScale(pulse: pulse, reduceMotion: true) == 1)
            #expect(abs(NeoListeningLayout.glowOpacity(pulse: pulse, reduceMotion: true) - NeoListeningLayout.reducedMotionPeakOpacity * pulse) < 1e-9)
        }
        #expect(NeoListeningLayout.glowOpacity(pulse: 0, reduceMotion: true) == 0)
    }

    @Test("the mark in each shape: the same pulse wherever the pet rides — fixed strips included — and nothing where the pet steps aside")
    func marks() {
        let indicator = listening()
        for state in [IslandState.idle, .wings, .compact, .expanded, .interactive, .appPanel, .meeting] {
            #expect(NeoListeningLayout.shows(in: state), "\(state)")
            for time in [0.0, 0.45, 1.0] {
                #expect(indicator.mark(for: state, at: at(time)) == NeoListeningMark(pulseStart: t0), "\(state) at \(time)")
            }
            for time in [1.4, 3.0, 600.0] {
                #expect(indicator.mark(for: state, at: at(time)) == nil, "\(state) at \(time)")
            }
        }
        // Exactly where the pet has no placement, the mark has none either.
        for state in IslandState.allCases {
            let pet = PetLayout.placement(for: state, islandSize: CGSize(width: 440, height: 300), notchHeight: 32)
            #expect(NeoListeningLayout.shows(in: state) == (pet != nil), "\(state)")
            #expect((indicator.mark(for: state, at: at(0.45)) == nil) == (pet == nil), "\(state)")
        }
    }

    @Test("listening never changes a frame: in every shape, at every moment of the pulse and after it, the island is the one without NEO")
    func framesIdentical() {
        // The island's size is a function of its shape and its measured
        // content alone — the listening mark is not part of either.
        let indicator = listening()
        var docked = IslandContentSize.default
        docked.petDock = .home
        var dockedLeft = IslandContentSize.default
        dockedLeft.petDock = PetDock(side: .left, reach: PetLayout.idleDock)
        var wings = IslandContentSize(compactLead: 0, compactTrail: 0, wingSide: 96 + PetLayout.barSlot)
        wings.wingLead = 44
        let compact = IslandContentSize(compactLead: 36, compactTrail: 70 + PetLayout.barSlot, wingSide: 0)
        let contents: [(String, IslandState, IslandContentSize)] = [
            ("idle", .idle, docked), ("idle, left", .idle, dockedLeft),
            ("wings", .wings, wings), ("compact", .compact, compact), ("expanded", .expanded, .default),
        ]
        for (name, state, content) in contents {
            let plain = geometry.frame(for: state, content: content)
            for time in [0.0, 0.2, 0.45, 1.0, 1.39, 1.4, 3.0, 600.0] {
                // Whatever the mark is — a pulse or nothing — the content the
                // island is measured from, and so its frame, is unchanged.
                let mark = indicator.mark(for: state, at: at(time))
                #expect((mark != nil) == (time < 1.4), "\(name) at \(time)")
                #expect(geometry.frame(for: state, content: content) == plain, "\(name) at \(time)")
            }
        }
        // The idle dock is the pet's dock and nothing more, either side.
        #expect(geometry.frame(for: .idle, content: docked) == geometry.compactBar(lead: 0, trail: PetLayout.idleDock))
        #expect(geometry.frame(for: .idle, content: dockedLeft) == geometry.compactBar(lead: PetLayout.idleDock, trail: 0))
        // Every other shape: the default content gives the pre-NEO frames.
        #expect(geometry.frame(for: .idle, content: .default) == geometry.notchFrame)
        #expect(geometry.frame(for: .wings, content: .default) == geometry.wingsBar(sideWidth: NotchGeometry.wingWidth))
        #expect(geometry.frame(for: .compact, content: .default) == geometry.compactFrame)
        #expect(geometry.frame(for: .expanded, content: .default) == geometry.expandedFrame)
        for state in IslandState.allCases {
            #expect(geometry.frame(for: state, content: .default) == geometry.frame(for: state), "\(state)")
        }
        // The mark carries no measurement at all: only when its pulse began.
        #expect(Mirror(reflecting: NeoListeningMark(pulseStart: t0)).children.map(\.label) == ["pulseStart"])
    }

    @Test("the content size has no room for listening: only the pet's dock, the measured widths, and NEO's panel")
    func noListeningRoom() {
        let labels = Mirror(reflecting: IslandContentSize.default).children.compactMap(\.label)
        #expect(labels == ["compactLead", "compactTrail", "wingSide", "wingLead", "panelHeight", "petDock", "neoPanel"])
    }

    @Test("Ghost Mode hides the glow with the island: it adds no shape of its own")
    func ghost() {
        for state in IslandState.allCases where NeoListeningLayout.shows(in: state) {
            #expect(GhostMode.hidesFromCapture(state: state, ghostModeEnabled: true), "\(state)")
            #expect(!GhostMode.alwaysPrivate.contains(state), "\(state)")
        }
    }
}
