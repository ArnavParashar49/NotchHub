import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("NEO's wake light: the island's rim lit while NEO listens")
struct NeoWakeLightTests {

    /// The island shapes the light is drawn round, with the notch where it
    /// sits in each: the idle dock, the wings, a lopsided compact bar, the
    /// expanded island, and the fox hiding in the notch (island = notch).
    let notch = CGSize(width: 185, height: 32)
    var islands: [(name: String, size: CGSize, notch: CGRect)] {
        [
            ("idle", CGSize(width: 253, height: 32), CGRect(x: 34, y: 0, width: 185, height: 32)),
            ("wings", CGSize(width: 423, height: 32), CGRect(x: 119, y: 0, width: 185, height: 32)),
            ("compact", CGSize(width: 459, height: 32), CGRect(x: 150, y: 0, width: 185, height: 32)),
            ("expanded", CGSize(width: 514, height: 98), CGRect(x: 164.5, y: 0, width: 185, height: 32)),
            ("notch", CGSize(width: 185, height: 32), CGRect(x: 0, y: 0, width: 185, height: 32)),
        ]
    }
    let settled = NeoWakeLight.Phase(clock: 2.3)

    @Test("at rest the rim is dark at the top ends and brightest along the bottom")
    func restingShape() {
        for island in islands {
            for half in NeoWakeLight.Half.allCases {
                let top = NeoWakeLight.sample(at: 0, half: half, size: island.size, phase: settled, notch: island.notch)
                #expect(top.alpha < 0.01, "\(island.name) \(half): top end lit \(top.alpha)")
                let corner = NeoWakeLight.cornerLocation(size: island.size, notch: island.notch)
                let bottom = NeoWakeLight.sample(at: min(1, corner + 0.05), half: half, size: island.size, phase: settled, notch: island.notch)
                #expect(bottom.alpha > 0.5, "\(island.name) \(half): bottom only \(bottom.alpha)")
            }
        }
        // Without the highlight (Reduce Motion), it only ever brightens from
        // the top end down to the bottom.
        let still = NeoWakeLight.Phase(clock: 0, reduceMotion: true)
        for island in islands {
            let stops = NeoWakeLight.stops(half: .leading, size: island.size, phase: still, notch: island.notch)
            for (a, b) in zip(stops, stops.dropFirst()) where b.location <= NeoWakeLight.cornerLocation(size: island.size, notch: island.notch) {
                #expect(b.alpha >= a.alpha - 1e-9, "\(island.name): dims going down the side at \(b.location)")
            }
        }
    }

    @Test("every value is light, 0 … 1, through the wake, the rest and the exit")
    func bounded() {
        for island in islands {
            for clock in stride(from: 0.0, through: 10, by: 0.37) {
                for phase in [
                    NeoWakeLight.Phase(clock: clock),
                    NeoWakeLight.Phase(clock: clock, wake: min(clock, NeoWakeLight.enterDuration - 0.01)),
                    NeoWakeLight.Phase(clock: clock, fade: 0.4),
                ] {
                    for half in NeoWakeLight.Half.allCases {
                        for stop in NeoWakeLight.stops(half: half, size: island.size, phase: phase, notch: island.notch) {
                            #expect((0...1).contains(stop.alpha) && (0...1).contains(stop.white) && (0...1).contains(stop.clear))
                            #expect((0...1).contains(stop.location))
                        }
                    }
                }
            }
        }
    }

    @Test("one loop of the resting light repeats seamlessly")
    func loopSeamless() {
        for island in islands {
            for clock in [0.0, 1.3, 4.8, 7.7] {
                let a = NeoWakeLight.stops(half: .trailing, size: island.size, phase: .init(clock: clock), notch: island.notch)
                let b = NeoWakeLight.stops(half: .trailing, size: island.size, phase: .init(clock: clock + NeoWakeLight.loopDuration), notch: island.notch)
                #expect(a.count == b.count)
                for (x, y) in zip(a, b) {
                    #expect(abs(x.alpha - y.alpha) < 1e-6 && abs(x.white - y.white) < 1e-6)
                }
            }
        }
        #expect(NeoWakeLight.loopDuration.truncatingRemainder(dividingBy: NeoWakeLight.breathPeriod) == 0)
    }

    @Test("the two halves agree where they meet, under the middle of the notch")
    func halvesMeet() {
        for island in islands {
            for clock in stride(from: 0.0, through: 9.6, by: 0.8) {
                for phase in [NeoWakeLight.Phase(clock: clock), NeoWakeLight.Phase(clock: clock, wake: clock / 7)] {
                    let left = NeoWakeLight.sample(at: 1, half: .leading, size: island.size, phase: phase, notch: island.notch)
                    let right = NeoWakeLight.sample(at: 1, half: .trailing, size: island.size, phase: phase, notch: island.notch)
                    #expect(abs(left.alpha - right.alpha) < 1e-9 && abs(left.white - right.white) < 1e-9 && abs(left.clear - right.clear) < 1e-9,
                            "\(island.name) at \(clock): \(left) vs \(right)")
                }
            }
            #expect(NeoWakeLight.split(size: island.size, notch: island.notch) == Double(island.notch.midX))
        }
        // No notch: the island's own middle.
        #expect(NeoWakeLight.split(size: CGSize(width: 300, height: 32), notch: nil) == 150)
    }

    @Test("the wake: dark at first, one sweep from the top ends to the meeting, then exactly the settled light")
    func wake() {
        let island = islands[1]
        let first = NeoWakeLight.stops(half: .leading, size: island.size, phase: .init(clock: 0, wake: 0), notch: island.notch)
        #expect(first.allSatisfy { $0.alpha < 0.05 }, "lit before the sweep")
        var last = -1.0
        for t in stride(from: 0.0, through: NeoWakeLight.arrival, by: 0.02) {
            let head = NeoWakeLight.headPosition(wake: t)
            #expect(head >= last)
            last = head
        }
        #expect(NeoWakeLight.headPosition(wake: 0) < 1e-6 && abs(NeoWakeLight.headPosition(wake: NeoWakeLight.arrival) - 1) < 1e-6)
        #expect(abs(NeoWakeLight.headPosition(wake: NeoWakeLight.wakeTime(headAt: 0.4)) - 0.4) < 1e-4)
        // Ahead of the sweep the rim is still dark; behind it, lit.
        let midway = NeoWakeLight.wakeTime(headAt: 0.5)
        let ahead = NeoWakeLight.sample(at: 0.8, half: .leading, size: island.size, phase: .init(clock: midway, wake: midway), notch: nil)
        let behind = NeoWakeLight.sample(at: 0.3, half: .leading, size: island.size, phase: .init(clock: midway, wake: midway), notch: nil)
        #expect(ahead.alpha < 0.05 && behind.alpha > 0.3)
        // The end of the wake is the settled light: no jump when it ends.
        let end = NeoWakeLight.enterDuration - 1e-6
        for location in stride(from: 0.0, through: 1, by: 0.01) {
            let x = NeoWakeLight.sample(at: location, half: .leading, size: island.size, phase: .init(clock: end, wake: end), notch: island.notch)
            let y = NeoWakeLight.sample(at: location, half: .leading, size: island.size, phase: .init(clock: end), notch: island.notch)
            #expect(abs(x.alpha - y.alpha) < 1e-3 && abs(x.white - y.white) < 1e-3, "jump at \(location): \(x.alpha) → \(y.alpha)")
        }
    }

    @Test("entrance and exit progress, and the phases they give")
    func activation() {
        #expect(NeoWakeLight.activation(seconds: 0, appearing: true) == 0)
        #expect(NeoWakeLight.activation(seconds: NeoWakeLight.enterDuration, appearing: true) == 1)
        #expect(NeoWakeLight.activation(seconds: 0, appearing: false) == 1)
        #expect(NeoWakeLight.activation(seconds: NeoWakeLight.exitDuration, appearing: false) == 0)
        #expect(NeoWakeLight.activation(seconds: NeoWakeLight.reduceMotionFade / 2, appearing: true, reduceMotion: true) == 0.5)
        let waking = NeoWakeLight.phase(clock: 0.3, activation: 0.3 / NeoWakeLight.enterDuration, listening: true, reduceMotion: false)
        #expect(waking.wake != nil && abs(waking.wake! - 0.3) < 1e-9 && waking.fade == 1)
        #expect(NeoWakeLight.phase(clock: 5, activation: 1, listening: true, reduceMotion: false).wake == nil)
        // The exit fades as progress² and ends dark.
        #expect(NeoWakeLight.phase(clock: 5, activation: 0.5, listening: false, reduceMotion: false).fade == 0.25)
        let gone = NeoWakeLight.phase(clock: 5, activation: 0, listening: false, reduceMotion: false)
        for island in islands {
            #expect(NeoWakeLight.stops(half: .leading, size: island.size, phase: gone, notch: island.notch).allSatisfy { $0.alpha == 0 })
        }
    }

    @Test("Reduce Motion: a still rim, the same at every moment")
    func reduceMotion() {
        let island = islands[3]
        let a = NeoWakeLight.stops(half: .leading, size: island.size, phase: .init(clock: 0, reduceMotion: true), notch: island.notch)
        let b = NeoWakeLight.stops(half: .leading, size: island.size, phase: .init(clock: 3.7, wake: 0.2, reduceMotion: true), notch: island.notch)
        #expect(a == b)
        #expect(a.last!.alpha > 0.7)
    }

    @Test("the glow keeps off the hardware notch, and only where the notch covers the rim")
    func glowOffTheNotch() {
        // The wings: the bottom edge under the notch is covered; well beside it, clear.
        let wings = islands[1]
        let under = NeoWakeLight.sample(at: 1, half: .leading, size: wings.size, phase: settled, notch: wings.notch)
        #expect(under.clear == 0)
        let reach = NeoWakeLight.reach(half: .leading, size: wings.size, split: Double(wings.notch.midX))
        let beside = NeoWakeLight.sample(at: (32 + 60) / reach, half: .leading, size: wings.size, phase: settled, notch: wings.notch)
        #expect(beside.clear == 1)
        // The island IS the notch: the glow is covered all the way round.
        let hiding = islands[4]
        for half in NeoWakeLight.Half.allCases {
            #expect(NeoWakeLight.stops(half: half, size: hiding.size, phase: settled, notch: hiding.notch).allSatisfy { $0.clear == 0 })
        }
        // The expanded island hangs below the notch: nothing to keep off.
        let expanded = islands[3]
        for half in NeoWakeLight.Half.allCases {
            #expect(NeoWakeLight.stops(half: half, size: expanded.size, phase: settled, notch: expanded.notch).allSatisfy { $0.clear == 1 })
        }
    }
}
