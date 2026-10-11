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

    @Test("the halves meet on a device-pixel boundary of the light's canvas, so no seam opens where they abut")
    func pixelAlignedMeeting() {
        // The expanded island is often a fraction of a point wide (514.08 pt
        // centred under the notch puts the notch's middle at 257.04): there
        // the two halves' antialiased ends shared a device pixel and left it
        // 6-10/255 darker.
        let cases: [(CGSize, CGRect)] = [
            (CGSize(width: 514.08, height: 98), CGRect(x: 164.54, y: 0, width: 185, height: 32)),
            (CGSize(width: 423.3, height: 32), CGRect(x: 119.15, y: 0, width: 185, height: 32)),
            (CGSize(width: 253, height: 32), CGRect(x: 34, y: 0, width: 185, height: 32)),
            (CGSize(width: 185, height: 32), CGRect(x: 0, y: 0, width: 185, height: 32)),
        ]
        for scale in [1.0, 2.0, 3.0] {
            for (size, notch) in cases {
                let aligned = NeoWakeLight.pixelAligned(notch: notch, size: size, scale: scale)!
                let split = NeoWakeLight.split(size: size, notch: aligned)
                #expect(abs(split * scale - (split * scale).rounded()) < 1e-9, "\(size) at \(scale)x: meets at \(split)")
                #expect(abs(aligned.midX - notch.midX) <= 0.5 / scale + 1e-9 && aligned.size == notch.size && aligned.minY == notch.minY)
            }
        }
        // Already on the grid: untouched. No notch: nothing to move.
        let notch = CGRect(x: 34, y: 0, width: 185, height: 32)
        #expect(NeoWakeLight.pixelAligned(notch: notch, size: CGSize(width: 253, height: 32), scale: 2) == notch)
        #expect(NeoWakeLight.pixelAligned(notch: nil, size: CGSize(width: 253, height: 32), scale: 2) == nil)
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

    @Test("the atmosphere: a pale line, a saturated glow and a deeper haze, all from one tint")
    func palette() {
        let blue = NeoWakeLight.palette(tint: NeoWakeLight.Colour(DesignTokens.wakeLightRGB))
        let line = NeoWakeLight.OKLCH(blue.line), near = NeoWakeLight.OKLCH(blue.near), haze = NeoWakeLight.OKLCH(blue.haze)
        #expect(line.l > near.l && near.l > haze.l, "the line is the brightest, the haze the deepest")
        #expect(near.c > line.c && haze.c > line.c, "the glow and the haze are more saturated than the line")
        // Blue, not white: even the line at its hottest keeps blue well above red.
        let hottest = blue.line.whitened(NeoWakeLight.maxWhite)
        #expect(hottest.blue - hottest.red > 0.35, "\(String(format: "%06X", hottest.hex))")
        // Every glow setting keeps its own hue (a violet stays violet).
        let violet = NeoWakeLight.Colour(hex: 0xB18CFF)
        let violetHaze = NeoWakeLight.OKLCH(NeoWakeLight.palette(tint: violet).haze)
        #expect(abs(NeoWakeLight.angle(violetHaze.h, NeoWakeLight.OKLCH(violet).h)) < 8)
    }

    @Test("the default blue's palette is exactly the one the light was designed in")
    func defaultPalettePinned() {
        let blue = NeoWakeLight.palette(tint: NeoWakeLight.Colour(DesignTokens.wakeLightRGB))
        #expect([blue.line.hex, blue.near.hex, blue.haze.hex, blue.inner.hex] == [0x7DC5FF, 0x3E9EFF, 0x2670FF, 0x4EAEFF],
                "\([blue.line, blue.near, blue.haze, blue.inner].map { String(format: "%06X", $0.hex) })")
        // Every coloured swatch keeps its palette too (only neutral tints changed).
        let swatches: [(UInt32, [UInt32])] = [
            (0x3FD8C2, [0x62E8D0, 0x00CDB5, 0x009C8A, 0x42D9C1]),
            (0x6FA8FF, [0xA1D4FF, 0x73B5FF, 0x407FF7, 0x84C4FF]),
            (0xB18CFF, [0xCEC5FF, 0xB79EFF, 0x995CF6, 0xC1B0FF]),
            (0xFF7FA8, [0xFFB6CA, 0xFF83AA, 0xE5367D, 0xFF9BB8]),
            (0xFFC24D, [0xFDC357, 0xE4A400, 0xAE7C00, 0xEEB239]),
        ]
        for (tint, expected) in swatches {
            let p = NeoWakeLight.palette(tint: NeoWakeLight.Colour(hex: tint))
            #expect([p.line.hex, p.near.hex, p.haze.hex, p.inner.hex] == expected, "\(String(format: "%06X", tint))")
        }
    }

    @Test("a neutral glow (white, a cool white, a grey) stays neutral: no yellow cast, and a white lights a near-white line")
    func neutralTints() {
        // A pure white or grey has no hue: its OKLCH hue is noise (about 90°,
        // yellow), so any chroma the palette adds at that hue turns it khaki.
        for tint: UInt32 in [0xFFFFFF, 0x808080] {
            let p = NeoWakeLight.palette(tint: NeoWakeLight.Colour(hex: tint))
            for (name, c) in [("line", p.line), ("near", p.near), ("haze", p.haze), ("inner", p.inner)] {
                let spread = max(c.red, c.green, c.blue) - min(c.red, c.green, c.blue)
                #expect(spread <= 1.0 / 255, "\(String(format: "%06X", tint)) \(name) is tinted: \(String(format: "%06X", c.hex))")
            }
        }
        // The cool white keeps its own faint blue — never warmer than neutral,
        // and only a little more saturated than itself.
        let coolTint = NeoWakeLight.Colour(hex: 0xF2F6FF)
        let cool = NeoWakeLight.palette(tint: coolTint)
        for (name, c) in [("line", cool.line), ("near", cool.near), ("haze", cool.haze), ("inner", cool.inner)] {
            #expect(c.blue >= c.red && c.blue >= c.green, "F2F6FF \(name) leans warm: \(String(format: "%06X", c.hex))")
            let oklch = NeoWakeLight.OKLCH(c)
            #expect(oklch.c < 0.035, "F2F6FF \(name) too saturated: \(oklch.c)")
            #expect(abs(NeoWakeLight.angle(oklch.h, NeoWakeLight.OKLCH(coolTint).h)) < 25, "F2F6FF \(name) hue \(oklch.h)")
        }
        // A white glow lights a near-white line, still the brightest part;
        // a mid grey's line is as bright as a coloured tint's.
        let white = NeoWakeLight.palette(tint: NeoWakeLight.Colour(hex: 0xFFFFFF))
        let line = NeoWakeLight.OKLCH(white.line), near = NeoWakeLight.OKLCH(white.near), haze = NeoWakeLight.OKLCH(white.haze)
        #expect(line.l >= 0.94, "white's line only \(line.l)")
        #expect(line.l > near.l && near.l > haze.l)
        #expect(NeoWakeLight.OKLCH(cool.line).l > 0.9)
        let grey = NeoWakeLight.OKLCH(NeoWakeLight.palette(tint: NeoWakeLight.Colour(hex: 0x808080)).line)
        #expect(abs(grey.l - 0.76) < 0.005)
    }

    @Test("nested bands, drawn one over another, give each row its share of the light")
    func nestedBands() {
        for profile in [NeoWakeLight.nearProfile, NeoWakeLight.innerProfile] {
            #expect(!profile.isEmpty)
            let alphas = NeoWakeLight.nestedAlphas(profile)
            for row in profile.indices {
                // Row `row` is covered by bands row…last, composited source-over.
                let shown = alphas[row...].reduce(0.0) { $0 + $1 * (1 - $0) }
                #expect(abs(shown - profile[row]) < 1e-9, "row \(row): \(shown) for \(profile[row])")
            }
        }
    }

    /// A gradient's value at `location`: linear between its stops, as drawn.
    func drawn(_ stops: [NeoWakeLight.Stop], at location: Double) -> Double {
        guard let next = stops.firstIndex(where: { $0.location >= location }) else { return stops.last!.alpha }
        guard next > 0 else { return stops[0].alpha }
        let a = stops[next - 1], b = stops[next]
        return a.alpha + (b.alpha - a.alpha) * (location - a.location) / max(1e-12, b.location - a.location)
    }

    @Test("the haze's light is sampled on one fixed grid, fine enough to be the light, so it never steps when the wake ends")
    func hazeGrid() {
        for island in islands {
            for half in NeoWakeLight.Half.allCases {
                let rest = NeoWakeLight.hazeStops(half: half, size: island.size, phase: settled, notch: island.notch)
                let grid = rest.map(\.location)
                // The same places through the wake as after it (and, through
                // the wake, a few more round the sweep's head).
                for wake in stride(from: 0.0, to: NeoWakeLight.enterDuration, by: 0.03) {
                    let waking = NeoWakeLight.hazeStops(half: half, size: island.size, phase: .init(clock: wake, wake: wake), notch: island.notch)
                    let locations = Set(waking.map(\.location))
                    #expect(grid.allSatisfy(locations.contains), "\(island.name) \(half) at \(wake) s: grid moved")
                }
                for clock in [0.0, 3.1, 7.7] {
                    #expect(NeoWakeLight.hazeStops(half: half, size: island.size, phase: .init(clock: clock), notch: island.notch).map(\.location) == grid)
                }
                // No step when the wake ends and the head's stops go: under
                // an 8-bit step, drawn.
                let end = NeoWakeLight.enterDuration - 1e-6
                let before = NeoWakeLight.hazeStops(half: half, size: island.size, phase: .init(clock: end, wake: end), notch: island.notch)
                let after = NeoWakeLight.hazeStops(half: half, size: island.size, phase: .init(clock: end), notch: island.notch)
                for x in stride(from: 0.0, through: 1, by: 0.002) {
                    let step = abs(drawn(before, at: x) - drawn(after, at: x)) * NeoWakeLight.hazeLevel
                    #expect(step < 1.0 / 255, "\(island.name) \(half): a step of \(step * 255)/255 at \(x)")
                }
                // Drawn as a gradient, the resting haze is within an 8-bit step
                // or so of the light itself everywhere along the rim.
                for clock in stride(from: 0.0, to: NeoWakeLight.loopDuration, by: 0.4) {
                    let phase = NeoWakeLight.Phase(clock: clock)
                    let stops = NeoWakeLight.hazeStops(half: half, size: island.size, phase: phase, notch: island.notch)
                    var worst = 0.0
                    for x in stride(from: 0.0, through: 1, by: 0.001) {
                        let truth = NeoWakeLight.sample(at: x, half: half, size: island.size, phase: phase, notch: island.notch).alpha
                        worst = max(worst, abs(drawn(stops, at: x) - truth) * NeoWakeLight.hazeLevel)
                    }
                    #expect(worst < 4.0 / 255, "\(island.name) \(half) at \(clock) s: off the light by \(worst * 255)/255")
                }
            }
        }
    }

    @Test("the haze is blurred through the wake's sweep and masked once settled, crossfaded between")
    func hazeHandover() {
        #expect(NeoWakeLight.hazeMasked(NeoWakeLight.Phase(clock: 0, wake: 0)) == 0)
        #expect(NeoWakeLight.hazeMasked(NeoWakeLight.Phase(clock: 0.66, wake: 0.66)) == 0)
        #expect(NeoWakeLight.hazeMasked(settled) == 1)
        #expect(NeoWakeLight.hazeMasked(NeoWakeLight.Phase(clock: 0.2, wake: 0.2, reduceMotion: true)) == 1)
        var last = 0.0
        for step in 0...60 {
            let t = NeoWakeLight.enterDuration * Double(step) / 60
            let m = NeoWakeLight.hazeMasked(NeoWakeLight.Phase(clock: t, wake: t))
            #expect(m >= last && m - last < 0.2, "a step of \(m - last) at \(t) s")
            last = m
        }
    }

    @Test("the haze hands over to its mask only once the island holds still, and then gently, over a quarter second")
    func hazeSettling() {
        var view = NeoWakeLight.HazeSettling<Int>()
        // Springing: a new island every frame, at 120 Hz — never still, and
        // the mask takes none of the haze.
        var t = 0.0
        for shape in 0..<60 {
            let still = view.still(shape, at: t)
            let share = view.maskShare(ready: false, at: t)
            #expect(!still && share == 0)
            t += 1.0 / 120
        }
        // The same island drawn twice in one frame is not yet still; the
        // same island a frame later is, and stays so while it holds.
        let twiceInOneFrame = view.still(59, at: t - 1.0 / 120)
        let aFrameLater = view.still(59, at: t)
        let drawnAgain = view.still(59, at: t)
        #expect(!twiceInOneFrame && aFrameLater && drawnAgain)
        // The mask's share: none until the mask is ready, then rising from
        // the first frame it is — smoothly, a 60 Hz frame at a time.
        let notReady = view.maskShare(ready: false, at: t)
        #expect(notReady == 0)
        let ready = t + 0.004
        var last = 0.0
        for step in 0...20 {
            let now = ready + Double(step) / 60
            let still = view.still(59, at: now)
            let share = view.maskShare(ready: true, at: now)
            #expect(still && share >= last && share - last < 0.13, "a jump of \(share - last) at \(now - ready) s")
            if step == 0 { #expect(share == 0) }
            last = share
        }
        let half = view.maskShare(ready: true, at: ready + NeoWakeLight.hazeSettle / 2)
        let whole = view.maskShare(ready: true, at: ready + NeoWakeLight.hazeSettle)
        #expect(abs(half - 0.5) < 1e-9 && whole == 1)
        // A move hands the haze back at once, and the next rest ramps again.
        let moved = ready + 1
        let moving = view.still(60, at: moved)
        let movingShare = view.maskShare(ready: false, at: moved)
        let resting = view.still(60, at: moved + 0.01)
        let restingShare = view.maskShare(ready: true, at: moved + 0.01)
        let rested = view.maskShare(ready: true, at: moved + 0.01 + NeoWakeLight.hazeSettle)
        #expect(!moving && movingShare == 0 && resting && restingShare == 0 && rested == 1)

        // Per view: two islands drawn in turn (two screens, or a render
        // beside the live one) each hold still. One shared "last island"
        // saw them as moving every frame.
        var a = NeoWakeLight.HazeSettling<Int>(), b = NeoWakeLight.HazeSettling<Int>()
        for frame in 0..<4 {
            let now = Double(frame) / 60
            let aStill = a.still(1, at: now), bStill = b.still(2, at: now)
            #expect(aStill == (frame > 0) && bStill == (frame > 0), "frame \(frame)")
        }
    }

    @Test("the haze's three ways of being drawn always add up to the whole of it")
    func hazeShares() {
        // Waking: diffused (the light itself blurred); at rest: the mask,
        // once ready; at rest while the island springs or its mask is still
        // being made: the same shape blurred on the GPU.
        #expect(NeoWakeLight.hazeShares(phase: .init(clock: 0.2, wake: 0.2), maskShare: 0) == .init(diffused: 1, shaped: 0, mask: 0))
        #expect(NeoWakeLight.hazeShares(phase: settled, maskShare: 1) == .init(diffused: 0, shaped: 0, mask: 1))
        #expect(NeoWakeLight.hazeShares(phase: settled, maskShare: 0) == .init(diffused: 0, shaped: 1, mask: 0))
        for wake in stride(from: 0.0, through: NeoWakeLight.enterDuration, by: 0.05) {
            for share in [0.0, 0.3, 1.0] {
                let s = NeoWakeLight.hazeShares(phase: .init(clock: wake, wake: wake), maskShare: share)
                #expect(abs(s.diffused + s.shaped + s.mask - 1) < 1e-12 && min(s.diffused, s.shaped, s.mask) >= 0)
            }
        }
    }
}
