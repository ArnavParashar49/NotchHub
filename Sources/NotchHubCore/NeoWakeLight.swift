import CoreGraphics
import Foundation

/// NEO's wake light — the "quiet rim": while NEO listens, the island's own
/// edge is the light. There is no moving dash and no border; the rim simply
/// glows, brightest along the bottom and fading to nothing as it climbs to
/// the top ends, with one broad soft highlight drifting slowly to and fro
/// along it (light catching brushed metal) and the whole of it breathing,
/// barely. When NEO wakes, one bright sweep runs from both top ends down
/// the sides and along the bottom, meets itself at the bottom centre, and
/// blooms there — and that bloom IS the drifting highlight, which leaves
/// the centre and settles into its slow swing.
///
/// This is the light's arithmetic only, pure and clock-driven, so it can be
/// tested and so an offscreen render of any moment draws exactly what the
/// live view draws. `NeoWakeOutlineView` turns `stops(half:size:phase:)` into
/// two gradients, one per half of the rim.
///
/// WHERE ON THE RIM: each half of the rim — from its top end down the side
/// and along the bottom to where the halves meet — is measured by `D`, 0 at
/// the top end and 1 at the meeting point. `D` is the Manhattan distance
/// from the top end over the half's `reach` (height + the bottom's run to
/// the meeting point): down the side it grows with y, along the bottom with
/// x, so ONE straight gradient laid diagonally (45°) across a half of the
/// island follows that half of the rim exactly, corners included. That is
/// why the whole light is two gradients and no masks.
///
/// The halves meet under the middle of the hardware notch (`split`), not
/// at the island's own middle: that is the screen's centre line — a whole
/// device pixel, where two fills can abut without a seam — and it stays
/// put while an island that is wider on one side springs to another shape.
/// The wake's two sweeps meet there, under the camera.
public enum NeoWakeLight {

    /// One half of the rim: the leading (left) one or the trailing (right)
    /// one. They mirror each other in shape but not in time — the highlight
    /// swings from one to the other.
    public enum Half: Sendable, CaseIterable {
        case leading, trailing
    }

    /// The light at one place along a half of the rim.
    public struct Stop: Equatable, Sendable {
        /// `D`: 0 at the half's top end, 1 at the bottom centre.
        public var location: Double
        /// How bright, 0 (dark) … 1.
        public var alpha: Double
        /// How far the hot core leans from the tint towards white, 0 … 1.
        public var white: Double
        /// How much of the glow inside the line may show here, 0 … 1: none
        /// where the hardware notch covers the rim (it would hide it), easing
        /// back in over `notchFeather` beside it. The line never needs this —
        /// it lies outside the black, where the notch never reaches.
        public var clear: Double = 1
    }

    /// Where the light is in its life, at one moment.
    public struct Phase: Equatable, Sendable {
        /// The light's own clock, in seconds: since this wake (live), or the
        /// injected clock (offscreen). The highlight and the breathing run
        /// on it.
        public var clock: TimeInterval
        /// Seconds into the wake (the entrance), while it runs; `nil` once it
        /// has settled.
        public var wake: TimeInterval?
        /// Everything at once, 0 … 1: the exit's fade (or Reduce Motion's).
        public var fade: Double
        /// A static rim: no sweep, no highlight, no breathing.
        public var reduceMotion: Bool

        public init(clock: TimeInterval, wake: TimeInterval? = nil, fade: Double = 1, reduceMotion: Bool = false) {
            self.clock = clock
            self.wake = wake
            self.fade = fade
            self.reduceMotion = reduceMotion
        }
    }

    // MARK: - Timing

    /// One whole cycle of the resting light: the highlight swings out and
    /// back once and the rim breathes twice. Every periodic part divides it,
    /// so a recording of one loop repeats seamlessly.
    public static let loopDuration: TimeInterval = 9.6
    /// One slow breath of the whole rim — about the rate of calm breathing.
    public static let breathPeriod: TimeInterval = loopDuration / 2
    /// The wake, from dark to the settled rim: the sweep, the bloom where it
    /// meets itself, and the bloom easing into the highlight's swing.
    public static let enterDuration: TimeInterval = 1.5
    /// When the sweep reaches the bottom centre. It decelerates into it, so
    /// the two halves meet softly rather than colliding.
    public static let arrival: TimeInterval = 0.66
    /// Listening ends: the whole rim fades out, quick at first and soft at
    /// the end, while the highlight keeps drifting.
    public static let exitDuration: TimeInterval = 0.5
    /// With Reduce Motion the rim only fades, in and out, over this.
    public static let reduceMotionFade: TimeInterval = 0.4

    // MARK: - Levels

    /// The resting rim's brightness along the bottom (the brightest place).
    public static let restLevel: Double = 0.7
    /// With Reduce Motion there is no highlight, so the rim rests a little
    /// brighter to read as clearly.
    public static let reduceMotionLevel: Double = 0.8
    /// How much the breathing lifts and lowers the resting rim (±).
    public static let breathDepth: Double = 0.1
    /// The highlight's brightness at its crest, over the resting rim.
    public static let shimmerLevel: Double = 0.32
    /// How far the highlight swings either side of the centre, as a fraction
    /// of the island's width: its crest stays on the bottom edge.
    public static let shimmerReach: Double = 0.3
    /// The highlight's softness: its Gaussian width as a fraction of the
    /// island's width — broad, so it reads as a sheen, not a spot.
    public static let shimmerWidth: Double = 0.11
    /// How much brighter the highlight is at the bloom than when settled.
    public static let bloomBoost: Double = 0.9
    /// The sweep's head: sharp in front, a long soft tail behind, in `D`.
    public static let headLead: Double = 0.035
    public static let headTail: Double = 0.17

    // MARK: - Activation (entrance / exit progress)

    /// Entrance or exit progress `seconds` after listening began
    /// (`appearing`) or ended: 0 … 1, rising linearly over the entrance and
    /// falling linearly over the exit. The light's curves are applied by
    /// `phase(clock:activation:listening:reduceMotion:)`, so the live view
    /// and an offscreen render given the same progress draw the same frame.
    public static func activation(seconds: TimeInterval, appearing: Bool, reduceMotion: Bool = false) -> Double {
        let duration = reduceMotion ? reduceMotionFade : (appearing ? enterDuration : exitDuration)
        let p = clamp(seconds / duration)
        return appearing ? p : 1 - p
    }

    /// The phase for an entrance or exit progress (`activation`): while
    /// `listening`, the wake `activation × enterDuration` seconds in (settled
    /// at 1); after it, the exit's fade. The exit fades as (progress)² —
    /// most of the light goes at once, the last of it softly.
    public static func phase(clock: TimeInterval, activation: Double, listening: Bool, reduceMotion: Bool) -> Phase {
        let a = clamp(activation)
        if reduceMotion {
            return Phase(clock: clock, fade: smoothstep(0, 1, a), reduceMotion: true)
        }
        if listening {
            return Phase(clock: clock, wake: a < 1 ? a * enterDuration : nil)
        }
        return Phase(clock: clock, fade: exitFade(remaining: a))
    }

    /// The exit's fade with `remaining` (1 → 0) of it left.
    public static func exitFade(remaining: Double) -> Double {
        let a = clamp(remaining)
        return a * a
    }

    // MARK: - The light along the rim

    /// How finely each half's gradient is sampled. The softest feature (the
    /// highlight) spans ten or more samples; the sweep's sharp front and the
    /// glow's fade beside the notch get extra ones.
    public static let samples = 48
    /// How far beside the hardware notch the glow has faded in again, in points.
    public static let notchFeather: Double = 18

    /// Where the halves meet across an island `size` wide: under the middle
    /// of the notch when there is one, kept on the bottom edge.
    public static func split(size: CGSize, notch: CGRect?) -> Double {
        let width = max(1, Double(size.width))
        guard let notch else { return width / 2 }
        return min(width - 0.5, max(0.5, Double(notch.midX)))
    }

    /// How far a half runs, in points of Manhattan distance: down its side
    /// and along the bottom to the meeting point.
    public static func reach(half: Half, size: CGSize, split: Double) -> Double {
        let width = max(1, Double(size.width)), height = max(1, Double(size.height))
        return height + (half == .leading ? split : width - split)
    }

    /// The light along one half of the rim of an island `size` (points), at
    /// `phase`, as gradient stops in `D` order (0 = the top end, 1 = where
    /// the halves meet). `notch` is the hardware notch in the island's
    /// coordinates: the halves meet under its middle, and the glow keeps
    /// off it.
    public static func stops(half: Half, size: CGSize, phase: Phase, notch: CGRect? = nil) -> [Stop] {
        var locations = (0...samples).map { Double($0) / Double(samples) }
        let width = max(1, Double(size.width)), height = max(1, Double(size.height))
        let reach = reach(half: half, size: size, split: split(size: size, notch: notch))
        if let wake = phase.wake, !phase.reduceMotion {
            // The sweep's sharp front: sample it finely wherever it is.
            let head = headPosition(wake: wake)
            locations += (-6...6).map { head + Double($0) * headLead * 0.5 }
        }
        if let notch {
            // The glow's fade beside the notch, along the bottom.
            let edge = half == .leading ? Double(notch.minX) : width - Double(notch.maxX)
            locations += (0...6).map { (height + edge - notchFeather * Double($0) / 6) / reach }
        }
        locations = locations.filter { $0 >= 0 && $0 <= 1 }.sorted()
        return locations.map { sample(at: $0, half: half, size: size, phase: phase, notch: notch) }
    }

    /// The light at `location` (`D`) along `half`.
    public static func sample(at location: Double, half: Half, size: CGSize, phase: Phase, notch: CGRect? = nil) -> Stop {
        let width = max(1, Double(size.width)), height = max(1, Double(size.height))
        let reach = reach(half: half, size: size, split: split(size: size, notch: notch))
        // Where that is: up the side (v, 0 at the top end → 1 at the bottom
        // corner) and across (u, 0 at the leading edge → 1 at the trailing
        // one; past the edge — negative, or over 1 — up the side, measured
        // round the corner).
        let along = location * reach
        let fromEdge = (along - height) / width
        let u = half == .leading ? fromEdge : 1 - fromEdge
        let v = min(1, along / height)
        let rise = pow(smoothstep(0.08, 0.9, v), 0.75)
        // Brightest along the bottom and a touch more at its middle; the
        // sides climb to nothing at the top ends.
        let middle = sin(.pi * clamp(u))
        let base = rise * (0.8 + 0.2 * middle * middle)

        // The glow's clearance from the hardware notch: none where the rim
        // runs under it (the bottom at the notch's own height, or a side
        // inside its span), easing in beside it and as the bottom drops
        // below it.
        var clear = 1.0
        if let notch {
            let x = half == .leading ? fromEdge * width : width - fromEdge * width
            let pointX = along < height ? (half == .leading ? 0 : width) : x
            let pointY = min(along, height)
            let outside = max(Double(notch.minX) - pointX, pointX - Double(notch.maxX))
            let beside = smoothstep(0, notchFeather, outside)
            let below = smoothstep(Double(notch.maxY), Double(notch.maxY) + 6, pointY)
            clear = 1 - (1 - beside) * (1 - below)
        }

        if phase.reduceMotion {
            return Stop(location: location, alpha: clamp(reduceMotionLevel * base * phase.fade), white: 0.18, clear: clear)
        }

        let clock = phase.clock
        let breath = 1 + breathDepth * sin(2 * .pi * (clock - arrival) / breathPeriod)
        let crest = 0.5 + shimmerReach * sin(2 * .pi * (clock - arrival) / loopDuration)
        let sheen = exp(-pow((u - crest) / shimmerWidth, 2)) * rise

        var rest = restLevel * breath * base
        var shimmer = shimmerLevel * sheen
        var head = 0.0
        if let wake = phase.wake {
            let position = headPosition(wake: wake)
            // The rim fills in behind the sweep, and all of it once the
            // sweep has met itself.
            let behind = smoothstep(position + 0.03, position - 0.2, location)
            let reveal = behind + (1 - behind) * smoothstep(arrival - 0.05, arrival + 0.35, wake)
            rest *= reveal
            // The highlight is born at the meeting point as the bloom, and
            // eases to its settled brightness by the end of the wake.
            let born = smoothstep(arrival - 0.2, arrival + 0.05, wake)
            let bloom = smoothstep(arrival - 0.15, arrival + 0.08, wake) * (1 - smoothstep(arrival + 0.08, enterDuration, wake))
            shimmer *= born + bloomBoost * bloom
            // The sweep's head: it grows out of the top ends, and is gone by
            // the time the bloom has taken over.
            let shape = location <= position
                ? exp(-pow((position - location) / headTail, 2))
                : exp(-pow((location - position) / headLead, 2))
            let grown = smoothstep(0, 0.08, position)
            let spent = 1 - smoothstep(arrival - 0.05, arrival + 0.45, wake)
            head = 0.95 * grown * spent * shape
        }
        let alpha = clamp((rest + shimmer + head) * phase.fade)
        // The hot core pales towards white at the highlight and the sweep —
        // but never all the way: a white line would vanish on a white
        // wallpaper just when it should shine.
        let white = min(0.65, 0.15 + 0.3 * sheen * min(1, shimmer / shimmerLevel) + 0.5 * head)
        return Stop(location: location, alpha: alpha, white: white, clear: clear)
    }

    /// Where the sweep's head is, in `D`, `wake` seconds into the wake: from
    /// the top ends (0) to the bottom centre (1) at `arrival`, quick to leave
    /// and slow to land — it decelerates into the meeting.
    public static func headPosition(wake: TimeInterval) -> Double {
        cubicBezier(clamp(wake / arrival), 0.3, 0.1, 0.35, 1.0)
    }

    /// The moment of the wake (seconds) when the head is at `location` (`D`).
    public static func wakeTime(headAt location: Double) -> TimeInterval {
        let target = clamp(location)
        var lo = 0.0, hi = arrival
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if headPosition(wake: mid) < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// The highlight's crest across the island (0 = leading edge, 1 =
    /// trailing edge) at `clock`.
    public static func crest(at clock: TimeInterval) -> Double {
        0.5 + shimmerReach * sin(2 * .pi * (clock - arrival) / loopDuration)
    }

    /// Where the leading half's bottom corner is in `D` for an island
    /// `size`: where its side meets the bottom.
    public static func cornerLocation(size: CGSize, notch: CGRect? = nil) -> Double {
        let height = max(1, Double(size.height))
        return height / reach(half: .leading, size: size, split: split(size: size, notch: notch))
    }

    // MARK: - Curves

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    /// 0 at `edge0`, 1 at `edge1`, smooth (Hermite) between; either order.
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge0 != edge1 else { return x < edge0 ? 0 : 1 }
        let t = clamp((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    /// A CSS-style timing curve: the cubic Bézier from (0, 0) to (1, 1) with
    /// control points (x1, y1) and (x2, y2), evaluated at time `x`.
    public static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func bezier(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let r = 1 - s
            return 3 * r * r * s * p1 + 3 * r * s * s * p2 + s * s * s
        }
        let x = clamp(x)
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if bezier(mid, x1, x2) < x { lo = mid } else { hi = mid }
        }
        return bezier((lo + hi) / 2, y1, y2)
    }
}
