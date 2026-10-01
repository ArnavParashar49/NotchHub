import Foundation

// A hand port of the geometry engine in `thinking-orbs` 0.3.2 (MIT, Jakub
// Antalik — see THIRD_PARTY.md). The nine orb animations NEO shows are pure
// functions of (size, time, options) that return a finished list of circles
// and lines to draw; this file is that engine, function for function, so the
// orb in the notch is the same orb NEO draws in its own window. The painter
// lives in `OrbView`; nothing here imports a drawing framework.
//
// Fidelity rule: every expression keeps the JS evaluation order and the same
// constants, so a frame here matches the JS frame to floating-point noise.
// `Tests/NotchHubOrbsTests` compares both against frames dumped from the JS.

/// One circle to fill. `white` is the ink value (0 = darkest ink on paper);
/// on a dark substrate it is mirrored so near dots read bright.
public struct OrbDot: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var r: Double
    public var white: Double
    public var a: Double

    public init(x: Double, y: Double, z: Double, r: Double, white: Double, a: Double = 1) {
        self.x = x
        self.y = y
        self.z = z
        self.r = r
        self.white = white
        self.a = a
    }
}

/// One edge to stroke (the `connecting` web).
public struct OrbLine: Equatable, Sendable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double
    public var white: Double
    public var a: Double
    public var w: Double

    public init(x1: Double, y1: Double, x2: Double, y2: Double, white: Double, a: Double = 1, w: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
        self.white = white
        self.a = a
        self.w = w
    }
}

/// One rendered instant: lines are drawn first, then the dots, which are
/// already z-sorted far → near and radius-clamped.
public struct OrbFrame: Equatable, Sendable {
    public var dots: [OrbDot]
    public var lines: [OrbLine]

    public init(dots: [OrbDot], lines: [OrbLine]) {
        self.dots = dots
        self.lines = lines
    }
}

/// The nine shipped animations.
public enum OrbState: String, CaseIterable, Sendable {
    /// Particles on tilted orbits.
    case working
    /// A scan meridian sweeps a dotted globe.
    case searching
    /// Bands scramble in quarter turns, then click back solved.
    case solving
    /// A waveform rolls through latitude rings.
    case listening
    /// A constellation wires itself, packets running the edges.
    case connecting
    /// Three strands plait around the sphere.
    case weaving
    /// An undulating multi-band sash.
    case composing
    /// A face-on ring slowly morphing.
    case breathing
    /// A dotted outline morphs circle → triangle → square.
    case shaping

    /// The geometry each state is drawn with.
    public var mode: OrbMode {
        switch self {
        case .working: return .orbits
        case .searching: return .globe
        case .solving: return .rubik
        case .listening: return .wave
        case .connecting: return .web
        case .weaving: return .braid
        case .composing: return .ribbon
        case .breathing: return .ring
        case .shaping: return .morph
        }
    }
}

/// The geometries behind the states (`ring` shares `ribbon`'s, face-on).
public enum OrbMode: String, CaseIterable, Sendable {
    case orbits, globe, rubik, wave, web, braid, ribbon, ring, morph
}

/// The tuned size presets: separate designs, not a scale factor. 64 is the
/// chat-avatar scale, 20 the inline-text scale and 32 is interpolated between
/// them. The frame itself is drawn at any size; the preset picks the dot
/// count, dot size and speed tuning.
public enum OrbSizePreset: Int, CaseIterable, Sendable {
    case large = 64
    case medium = 32
    case small = 20

    /// The preset tuned nearest to a rendered size.
    public static func nearest(to size: Double) -> OrbSizePreset {
        allCases.min { abs(Double($0.rawValue) - size) < abs(Double($1.rawValue) - size) } ?? .large
    }
}

/// The engine's draw options: a flat bag of numeric knobs, exactly as the JS
/// `ModeOpts` object. Keys a mode does not read are ignored.
public typealias OrbOptions = [String: Double]

/// A (state, size) pair resolved to its geometry, baked speed and options.
public struct OrbPreset: Equatable, Sendable {
    public var mode: OrbMode
    public var speed: Double
    public var opts: OrbOptions
}

public enum OrbEngine {

    // MARK: - Math helpers

    static func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }

    static func frac(_ x: Double) -> Double { x - floor(x) }

    /// Deterministic hash in [0, 1).
    static func hashD(_ a: Double, _ b: Double) -> Double {
        let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return h - floor(h)
    }

    /// Value noise on a 2D lattice — smooth, deterministic, cheap.
    static func vnoise(_ x: Double, _ y: Double) -> Double {
        let xi = floor(x)
        let yi = floor(y)
        var fx = x - xi
        var fy = y - yi
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        let a = hashD(xi, yi)
        let b = hashD(xi + 1, yi)
        let c = hashD(xi, yi + 1)
        let d = hashD(xi + 1, yi + 1)
        return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
    }

    /// Stable directions on a unit sphere (Fibonacci lattice).
    static func fibDir(_ i: Double, _ n: Double) -> (Double, Double, Double) {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let y = 1 - 2 * (i + 0.5) / n
        let rad = (1 - y * y).squareRoot()
        let a = i * golden
        return (rad * cos(a), y, rad * sin(a))
    }

    /// Shortest signed angular distance, wrapped to (-π, π].
    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        atan2(sin(a - b), cos(a - b))
    }

    /// Shared spin + tilt + orthographic projection.
    static func makeProj(yaw: Double, tilt: Double, cx: Double, cy: Double, scale: Double) -> (Double, Double, Double) -> (Double, Double, Double) {
        let st = sin(tilt)
        let ct = cos(tilt)
        let sy = sin(yaw)
        let cyw = cos(yaw)
        return { x, y, z in
            let x1 = x * cyw + z * sy
            let z1 = -x * sy + z * cyw
            let y1 = y * ct - z1 * st
            let z2 = y * st + z1 * ct
            return (cx + x1 * scale, cy - y1 * scale, z2)
        }
    }

    /// JS `Math.round`: half rounds toward +∞ (every value here is positive).
    static func jsRound(_ x: Double) -> Double { floor(x + 0.5) }

    /// JS `%` on doubles: the remainder keeps the dividend's sign.
    static func jsMod(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }

    // MARK: - Finishing a frame

    /// Drops invisible marks, clamps radii to the mode's floor, and z-sorts
    /// far → near into draw order. The sort is stable, as JS's is, so dots at
    /// equal depth keep their emission order.
    public static func finalizeFrame(_ dots: [OrbDot], _ lines: [OrbLine], rMin: Double = 0.3) -> OrbFrame {
        var visible: [OrbDot] = []
        visible.reserveCapacity(dots.count)
        for var d in dots {
            if d.a < 0.02 { continue }
            d.r = max(rMin, d.r)
            visible.append(d)
        }
        let sorted = visible.enumerated()
            .sorted { lhs, rhs in
                lhs.element.z == rhs.element.z ? lhs.offset < rhs.offset : lhs.element.z < rhs.element.z
            }
            .map(\.element)
        return OrbFrame(dots: sorted, lines: lines.filter { $0.a >= 0.02 })
    }

    /// Dot radii were tuned for a 300pt frame; sub-linear scaling keeps small
    /// spinners legible.
    public static func radiusScale(_ size: Double, _ pow: Double) -> Double {
        Foundation.pow(size / 300, pow)
    }

    // MARK: - Profiles & presets

    static let countPairs: [(String, String)] = [("latRings", "lonDensity"), ("rings", "lonDensity"), ("lanes", "segs")]
    static let countKeys = ["orbitN", "ghostN", "nodeN", "strandN", "signals"]
    static let iconDensityKeys = ["iconD"]
    static let radiusKeys = ["rBase", "rDepth", "rActive", "rDot", "ghostR", "partR", "partRDepth", "nodeR", "nodeRDepth"]

    public static func scaleCounts(_ opts: OrbOptions, _ scale: Double) -> OrbOptions {
        var out = opts
        var done = Set<String>()
        let rt = scale.squareRoot()
        for (a, b) in countPairs {
            if let va = out[a], let vb = out[b], !done.contains(a), !done.contains(b) {
                out[a] = max(2, jsRound(va * rt))
                out[b] = max(2, jsRound(vb * rt))
                done.insert(a)
                done.insert(b)
            }
        }
        for k in countKeys {
            if let v = out[k], v != 0, !done.contains(k) { out[k] = max(1, jsRound(v * scale)) }
        }
        for k in iconDensityKeys {
            if let v = out[k] { out[k] = max(0.02, v * scale) }
        }
        return out
    }

    public static func scaleRadii(_ opts: OrbOptions, _ scale: Double) -> OrbOptions {
        var out = opts
        for k in radiusKeys {
            if let v = out[k] { out[k] = v * scale }
        }
        out["rSizeMul"] = (out["rSizeMul"] ?? 1) * scale
        return out
    }

    /// Base (fine) profiles per mode, before preset multipliers.
    public static let baseProfiles: [OrbMode: OrbOptions] = [
        .globe: ["latRings": 17, "lonDensity": 44, "rBase": 0.6, "rDepth": 1.7, "rBoost": 1, "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3],
        .orbits: ["orbitN": 12, "ghostN": 40, "ghostR": 0.9, "ghostA": 0.5, "particles": 3, "partR": 1.2, "partRDepth": 1.6, "rsPow": 0.6, "rMin": 0.3],
        .rubik: ["latRings": 15, "lonDensity": 40, "moveCount": 14, "rBase": 0.6, "rDepth": 1.7, "rActive": 0.3, "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3],
        .wave: ["rings": 15, "lonDensity": 40, "rBase": 0.6, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
        .web: ["nodeN": 30, "thr": 0.72, "signals": 5, "nodeR": 1.4, "nodeRDepth": 1.8, "lineW": 0.8, "rsPow": 0.6, "rMin": 0.3],
        .braid: ["strandN": 52, "turns": 3, "ghostN": 150, "rBase": 1.2, "rDepth": 1.8, "rsPow": 0.6, "rMin": 0.3],
        .ribbon: ["lanes": 5, "segs": 88, "ghostN": 150, "rBase": 1.1, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
        // ring shares ribbon's painter; faceOn cancels the camera tilt and
        // moves the undulation onto the radius, and there is no ghost sphere.
        .ring: ["lanes": 5, "segs": 88, "ghostN": 0, "faceOn": 1, "rBase": 1.1, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
        .morph: ["rDot": 0.021, "iconD": 1, "rMin": 0.25],
    ]

    struct Preset {
        var speed: Double
        var count: Double
        var size: Double
        var extra: OrbOptions = [:]
    }

    static let presets: [OrbMode: [OrbSizePreset: Preset]] = [
        .orbits: [
            .large: Preset(speed: 1.885, count: 1, size: 1),
            .medium: Preset(speed: 2.9072, count: 0.4251, size: 1.6849),
            .small: Preset(speed: 3.9, count: 0.238, size: 2.4),
        ],
        .globe: [
            .large: Preset(speed: 2.015, count: 0.42, size: 1.15, extra: ["scanMul": 4.08, "dimBase": 0.45]),
            .medium: Preset(speed: 2.3803, count: 0.1839, size: 1.4769, extra: ["scanMul": 4.2301, "dimBase": 0.45]),
            .small: Preset(speed: 2.665, count: 0.105, size: 1.75, extra: ["scanMul": 4.335, "dimBase": 0.45]),
        ],
        .rubik: [
            .large: Preset(speed: 1.82, count: 0.35, size: 1.05),
            .medium: Preset(speed: 1.8964, count: 0.1537, size: 1.4951),
            .small: Preset(speed: 1.95, count: 0.088, size: 1.9),
        ],
        .wave: [
            .large: Preset(speed: 4.388, count: 0.341, size: 1),
            .medium: Preset(speed: 4.1512, count: 0.169, size: 1.3232),
            .small: Preset(speed: 3.998, count: 0.105, size: 1.6),
        ],
        .web: [
            .large: Preset(speed: 3.315, count: 1.35, size: 0.95),
            .medium: Preset(speed: 5.0104, count: 0.4942, size: 1.2571),
            .small: Preset(speed: 6.63, count: 0.25, size: 1.52),
        ],
        .braid: [
            .large: Preset(speed: 1.625, count: 0.5, size: 1),
            .medium: Preset(speed: 2.2234, count: 0.2056, size: 1.2011),
            .small: Preset(speed: 2.75, count: 0.1125, size: 1.36),
        ],
        .ribbon: [
            .large: Preset(speed: 2.34, count: 0.25, size: 0.85, extra: ["spin": 0, "bandMul": 3.9, "wobMul": 1]),
            .medium: Preset(speed: 2.7776, count: 0.0969, size: 0.9766, extra: ["spin": 0, "bandMul": 4.49, "wobMul": 1]),
            .small: Preset(speed: 3.12, count: 0.051, size: 1.073, extra: ["spin": 0, "bandMul": 4.94, "wobMul": 1]),
        ],
        .ring: [
            .large: Preset(speed: 3.24, count: 0.25, size: 0.956, extra: ["spin": 0, "bandMul": 3.627, "wobMul": 0.368]),
            .medium: Preset(speed: 3.5517, count: 0.0678, size: 1.31, extra: ["spin": 0, "bandMul": 3.8265, "wobMul": 0.4751]),
            .small: Preset(speed: 3.78, count: 0.028, size: 1.622, extra: ["spin": 0, "bandMul": 3.968, "wobMul": 0.565]),
        ],
        .morph: [
            .large: Preset(speed: 2.405, count: 0.702, size: 0.395, extra: ["spread": 1.45]),
            .medium: Preset(speed: 2.2057, count: 0.5937, size: 0.6916, extra: ["spread": 1.45]),
            .small: Preset(speed: 2.08, count: 0.53, size: 1.011, extra: ["spread": 1.45]),
        ],
    ]

    /// Resolves a (state, size) pair to its mode + fully-scaled draw options.
    public static func resolvePreset(state: OrbState, size: OrbSizePreset) -> OrbPreset {
        let mode = state.mode
        let preset = presets[mode]![size]!
        var opts = baseProfiles[mode]!
        if preset.count != 1 { opts = scaleCounts(opts, preset.count) }
        if preset.size != 1 { opts = scaleRadii(opts, preset.size) }
        for (k, v) in preset.extra { opts[k] = v }
        return OrbPreset(mode: mode, speed: preset.speed, opts: opts)
    }

    // MARK: - Frames

    /// The geometry of one instant: `size` in points, `t` the animation time
    /// (already multiplied by the preset's speed), `o` the resolved options.
    public static func frame(mode: OrbMode, size: Double, t: Double, opts o: OrbOptions) -> OrbFrame {
        switch mode {
        case .orbits: return frameOrbits(size, t, o)
        case .globe: return frameGlobe(size, t, o)
        case .rubik: return frameRubik(size, t, o)
        case .wave: return frameWave(size, t, o)
        case .web: return frameWeb(size, t, o)
        case .braid: return frameBraid(size, t, o)
        case .ribbon, .ring: return frameRibbon(size, t, o)
        case .morph: return frameMorph(size, t, o)
        }
    }

    static func frameBraid(_ size: Double, _ t: Double, _ o: OrbOptions) -> OrbFrame {
        let cx = size / 2
        let cy = size / 2
        let R = size / 2 * 0.76
        let pt = makeProj(yaw: t * 0.4, tilt: 0.3, cx: cx, cy: cy, scale: 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let ghostN = Int(o["ghostN"] ?? 150)
        for i in 0..<ghostN {
            let d = fibDir(Double(i), Double(ghostN))
            let (px, py, z) = pt(d.0 * R, d.1 * R, d.2 * R)
            let depth = (z / R + 1) / 2
            dots.append(OrbDot(x: px, y: py, z: z, r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth))
        }
        let strandN = Int(o["strandN"] ?? 52)
        let turns = o["turns"] ?? 3
        for s in 0..<3 {
            let phase = Double(s) / 3 * 2 * Double.pi
            for i in 0..<strandN {
                let u = (frac(Double(i) / Double(strandN) + t * 0.045) * 2 - 1) * 0.96
                let surf = max(0, 1 - u * u).squareRoot()
                let endFade = min(1, (1 - abs(u)) / 0.1)
                let a = u * Double.pi * turns + phase
                let weave = 1 + 0.075 * sin(u * Double.pi * turns * 2 + phase * 2 + t * 0.8)
                let rr = surf * R * weave
                let (px, py, zr) = pt(cos(a) * rr, u * R * weave, sin(a) * rr)
                let depth = (zr / R + 1) / 2
                dots.append(OrbDot(
                    x: px, y: py, z: zr,
                    r: ((o["rBase"] ?? 1.2) + (o["rDepth"] ?? 1.8) * depth) * rs,
                    white: 0.55 - 0.45 * depth,
                    a: endFade * (0.45 + 0.55 * depth)
                ))
            }
        }
        return finalizeFrame(dots, [], rMin: o["rMin"] ?? 0.3)
    }

    struct SolveCycle {
        var amount: [Double]
        var active: Int
    }

    static func solveCycle(_ time: Double, _ count: Int, _ slotDur: Double, _ rest: Double) -> SolveCycle {
        let cyc = 2 * Double(count) * slotDur + rest
        let tc = jsMod(time, cyc)
        var amount = [Double](repeating: 0, count: count)
        var active = -1
        if tc < 2 * Double(count) * slotDur {
            let slot = Int(floor(tc / slotDur))
            let p = (tc - Double(slot) * slotDur) / slotDur
            let cl = min(1, p / 0.7)
            let ep = 1 - Foundation.pow(1 - cl, 3)
            if slot < count {
                for i in 0..<slot { amount[i] = 1 }
                amount[slot] = ep
                active = slot
            } else {
                let u = 2 * count - 1 - slot
                for i in 0..<u { amount[i] = 1 }
                amount[u] = 1 - ep
                active = u
            }
        }
        return SolveCycle(amount: amount, active: active)
    }

    struct Move {
        var axis: Int
        var lo: Double
        var hi: Double
        var ang: Double
    }

    static func applyMoves(_ p: (Double, Double, Double), _ moves: [Move], _ sc: SolveCycle) -> (Double, Double, Double, Bool) {
        var (x, y, z) = p
        var inActive = false
        for i in 0..<moves.count {
            if sc.amount[i] <= 0 { continue }
            let mv = moves[i]
            let coord = mv.axis == 0 ? x : mv.axis == 1 ? y : z
            if coord < mv.lo || coord >= mv.hi { continue }
            if i == sc.active { inActive = true }
            let a = mv.ang * sc.amount[i]
            let ca = cos(a)
            let sa = sin(a)
            if mv.axis == 0 {
                let y2 = y * ca - z * sa
                z = y * sa + z * ca
                y = y2
            } else if mv.axis == 1 {
                let x2 = x * ca + z * sa
                z = -x * sa + z * ca
                x = x2
            } else {
                let x2 = x * ca - y * sa
                y = x * sa + y * ca
                x = x2
            }
        }
        return (x, y, z, inActive)
    }

    static func makeMoves(_ count: Int) -> [Move] {
        var moves: [Move] = []
        for i in 0..<count {
            let fi = Double(i)
            let axis = Int(min(2, floor(hashD(fi, 2.3) * 3)))
            let lo = -1 + 0.5 * min(3, floor(hashD(fi, 5.9) * 4))
            let dir: Double = hashD(fi, 7.7) < 0.5 ? 1 : -1
            moves.append(Move(axis: axis, lo: lo, hi: lo + 0.5, ang: dir * Double.pi / 2))
        }
        return moves
    }

    static func frameGlobe(_ size: Double, _ t: Double, _ o: OrbOptions) -> OrbFrame {
        let spin = 0.5
        let cx = size / 2
        let cy = size / 2
        let radius = size / 2 * 0.82
        let tilt = 0.4 + 0.06 * sin(t * 0.35)
        let pt = makeProj(yaw: t * spin, tilt: tilt, cx: cx, cy: cy, scale: radius)
        let scan = t * (spin + (1.7 - spin) * (o["scanMul"] ?? 1))
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        let dimBase = o["dimBase"] ?? 1
        var dots: [OrbDot] = []
        let latRings = Int(o["latRings"] ?? 17)
        let lonDensity = o["lonDensity"] ?? 44
        for li in 0...latRings {
            let lat = -Double.pi / 2 + Double(li) / Double(latRings) * Double.pi
            let cosLat = cos(lat)
            let sinLat = sin(lat)
            let lonCount = Int(max(1, jsRound(abs(cosLat) * lonDensity)))
            for lj in 0..<lonCount {
                let lon = Double(lj) / Double(lonCount) * 2 * Double.pi
                let (px, py, z) = pt(cosLat * cos(lon), sinLat, cosLat * sin(lon))
                let depth = (z + 1) / 2
                let d = angleDelta(lon + t * spin, scan)
                let boost = exp(-(d * d) / 0.18) * max(0, z)
                dots.append(OrbDot(
                    x: px, y: py, z: z,
                    r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (o["rBoost"] ?? 1) * boost) * rs,
                    white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth,
                    // dimBase < 1 fades un-scanned dots so the meridian reads clearly
                    a: dimBase + (1 - dimBase) * min(1, boost)
                ))
            }
        }
        return finalizeFrame(dots, [], rMin: o["rMin"] ?? 0.3)
    }

    static func frameRubik(_ size: Double, _ t: Double, _ o: OrbOptions) -> OrbFrame {
        let cx = size / 2
        let cy = size / 2
        let R = size / 2 * 0.82
        let pt = makeProj(yaw: t * 0.55, tilt: 0.35 + 0.1 * sin(t * 0.9), cx: cx, cy: cy, scale: R)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        let moveCount = Int(o["moveCount"] ?? 14)
        let moves = makeMoves(moveCount)
        let sc = solveCycle(t, moveCount, 0.42, 1.2)
        var dots: [OrbDot] = []
        let latRings = Int(o["latRings"] ?? 15)
        let lonDensity = o["lonDensity"] ?? 40
        for li in 0...latRings {
            let lat = -Double.pi / 2 + Double(li) / Double(latRings) * Double.pi
            let cosLat = cos(lat)
            let sinLat = sin(lat)
            let lonCount = Int(max(1, jsRound(abs(cosLat) * lonDensity)))
            for lj in 0..<lonCount {
                let lon = Double(lj) / Double(lonCount) * 2 * Double.pi
                let (x, y, z, inActive) = applyMoves((cosLat * cos(lon), sinLat, cosLat * sin(lon)), moves, sc)
                let (px, py, zr) = pt(x, y, z)
                let depth = (zr + 1) / 2
                dots.append(OrbDot(
                    x: px, y: py, z: zr,
                    r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (inActive ? (o["rActive"] ?? 0.3) : 0)) * rs,
                    white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth - (inActive ? 0.14 : 0)
                ))
            }
        }
        return finalizeFrame(dots, [], rMin: o["rMin"] ?? 0.3)
    }

    static func frameWave(_ size: Double, _ t: Double, _ o: OrbOptions) -> OrbFrame {
        let cx = size / 2
        let cy = size / 2
        let R = size / 2 * 0.874
        let pt = makeProj(yaw: t * 0.18, tilt: 0.38, cx: cx, cy: cy, scale: 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let rings = Int(o["rings"] ?? 15)
        let lonDensity = o["lonDensity"] ?? 40
        for ri in 0...rings {
            let lat = -Double.pi / 2 + Double(ri) / Double(rings) * Double.pi
            let cosLat = cos(lat)
            let sinLat = sin(lat)
            let w = 0.62 * sin(t * 2.1 - Double(ri) * 0.52) + 0.38 * sin(t * 1.27 + Double(ri) * 0.83)
            let rr = R * (0.88 + 0.105 * w)
            let lonCount = Int(max(1, jsRound(abs(cosLat) * lonDensity)))
            for lj in 0..<lonCount {
                let lon = Double(lj) / Double(lonCount) * 2 * Double.pi
                let (px, py, z) = pt(cosLat * cos(lon) * rr, sinLat * rr, cosLat * sin(lon) * rr)
                let depth = (z / R + 1) / 2
                let crest = max(0, w)
                dots.append(OrbDot(
                    x: px, y: py, z: z,
                    r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth) * (1 + 0.4 * crest) * rs,
                    white: 0.66 - 0.56 * depth - 0.1 * crest
                ))
            }
        }
        return finalizeFrame(dots, [], rMin: o["rMin"] ?? 0.3)
    }

    static func smoothE(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    typealias PathFn = (Double) -> (Double, Double)

    static func polyPath(_ verts: [(Double, Double)]) -> PathFn {
        let V = verts.count
        var L: [Double] = []
        for i in 0..<V {
            let a = verts[i]
            let b = verts[(i + 1) % V]
            L.append(((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot())
        }
        let total = L.reduce(0, +)
        return { f in
            var target = f * total
            var i = 0
            while target > L[i] && i < V - 1 {
                target -= L[i]
                i += 1
            }
            let a = verts[i]
            let b = verts[(i + 1) % V]
            let ff = L[i] != 0 ? min(1, target / L[i]) : 0
            return (a.0 + (b.0 - a.0) * ff, a.1 + (b.1 - a.1) * ff)
        }
    }

    static let circlePath: PathFn = { f in
        let a = -Double.pi / 2 + f * 2 * Double.pi
        return (cos(a) * 0.24, sin(a) * 0.24)
    }
    static let trianglePath: PathFn = polyPath([(0, -0.26), (0.24, 0.16), (-0.24, 0.16)])
    static let squarePath: PathFn = polyPath([(0, -0.2), (0.2, -0.2), (0.2, 0.2), (-0.2, 0.2), (-0.2, -0.2)])
    static let morphCycle: [PathFn] = [circlePath, trianglePath, squarePath]

    static func morphN(_ d: Double) -> Int { Int(max(6, jsRound(34 * d))) }

    static let morphHold = 1.4
    static let morphMorph = 0.9
    static let morphSeg = morphHold + morphMorph

    static func frameMorph(_ size: Double, _ t: Double, _ o: OrbOptions) -> OrbFrame {
        let K = morphCycle.count
        let tc = jsMod(t, morphSeg * Double(K))
        let held: Int
        if let shape = o["shape"], shape >= 0, shape < Double(K) { held = Int(floor(shape)) } else { held = -1 }
        let k = held >= 0 ? held : Int(floor(tc / morphSeg))
        let local = held >= 0 ? jsMod(t, morphSeg) : tc - Double(k) * morphSeg
        let m = held >= 0 ? 0 : (local > morphHold ? smoothE((local - morphHold) / morphMorph) : 0)
        let sprd = o["spread"] ?? 1
        let pA = morphCycle[k]
        let pB = held >= 0 ? pA : morphCycle[(k + 1) % K]
        let M = 160
        var pts: [(Double, Double)] = []
        pts.reserveCapacity(M)
        for i in 0..<M {
            let f = Double(i) / Double(M)
            let a = pA(f)
            let b = pB(f)
            pts.append(((a.0 + (b.0 - a.0) * m) * sprd, (a.1 + (b.1 - a.1) * m) * sprd))
        }
        var L: [Double] = []
        var total = 0.0
        for i in 0..<M {
            let a = pts[i]
            let b = pts[(i + 1) % M]
            let l = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
            L.append(l)
            total += l
        }
        let n = morphN(o["iconD"] ?? 1)
        let re = (o["rDot"] ?? 0.021) * 1.35 * sprd
        let pulse = 1 + 0.02 * sin(local * 3.1)
        var dots: [OrbDot] = []
        let c2 = size / 2
        var seg = 0
        var acc = 0.0
        for k2 in 0..<n {
            let target = Double(k2) / Double(n) * total
            while acc + L[seg] < target && seg < M - 1 {
                acc += L[seg]
                seg += 1
            }
            let a = pts[seg]
            let b = pts[(seg + 1) % M]
            let f = L[seg] != 0 ? min(1, (target - acc) / L[seg]) : 0
            let x = (a.0 + (b.0 - a.0) * f) * pulse
            let y = (a.1 + (b.1 - a.1) * f) * pulse
            dots.append(OrbDot(x: c2 + x * size, y: c2 + y * size, z: 0, r: max(0.35, re * size), white: 0.1))
        }
        return finalizeFrame(dots, [], rMin: o["rMin"] ?? 0.3)
    }

    static func frameOrbits(_ size: Double, _ t: Double, _ o: OrbOptions) -> OrbFrame {
        let cx = size / 2
        let cy = size / 2
        let R = size / 2 * 0.82
        let pt = makeProj(yaw: t * 0.12, tilt: 0.3, cx: cx, cy: cy, scale: 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let orbitN = Int(o["orbitN"] ?? 12)
        let ghostN = Int(o["ghostN"] ?? 40)
        let particles = Int(o["particles"] ?? 3)
        for orb in 0..<orbitN {
            let fo = Double(orb)
            let h1 = hashD(fo, 1.7)
            let h2 = hashD(fo, 5.2)
            let h3 = hashD(fo, 8.9)
            let ro = R * (0.45 + 0.52 * h1)
            let th = h1 * 2 * Double.pi
            let phi = acos(2 * h2 - 1)
            let nx = sin(phi) * cos(th)
            let ny = cos(phi)
            let nz = sin(phi) * sin(th)
            var ux = -ny
            var uy = nx
            let uz = 0.0
            let ul = max(1e-6, (ux * ux + uy * uy).squareRoot())
            ux /= ul
            uy /= ul
            let vx = ny * uz - nz * uy
            let vy = nz * ux - nx * uz
            let vz = nx * uy - ny * ux
            let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)
            for k in 0..<ghostN {
                let a = Double(k) / Double(ghostN) * 2 * Double.pi
                let (px, py, z) = pt(
                    (ux * cos(a) + vx * sin(a)) * ro,
                    (uy * cos(a) + vy * sin(a)) * ro,
                    (uz * cos(a) + vz * sin(a)) * ro
                )
                let depth = (z / ro + 1) / 2
                dots.append(OrbDot(
                    x: px, y: py, z: z,
                    r: (o["ghostR"] ?? 0.9) * rs,
                    white: 0.72,
                    a: (o["ghostA"] ?? 0.5) * (0.4 + 0.6 * depth)
                ))
            }
            for m in 0..<particles {
                let a = t * speed + Double(m) / Double(particles) * 2 * Double.pi + h2 * 6
                let (px, py, z) = pt(
                    (ux * cos(a) + vx * sin(a)) * ro,
                    (uy * cos(a) + vy * sin(a)) * ro,
                    (uz * cos(a) + vz * sin(a)) * ro
                )
                let depth = (z / ro + 1) / 2
                dots.append(OrbDot(
                    x: px, y: py, z: z,
                    r: ((o["partR"] ?? 1.2) + (o["partRDepth"] ?? 1.6) * depth) * rs,
                    white: 0.3 - 0.22 * depth
                ))
            }
        }
        return finalizeFrame(dots, [], rMin: o["rMin"] ?? 0.3)
    }

    static func frameRibbon(_ size: Double, _ t: Double, _ o: OrbOptions) -> OrbFrame {
        let cx = size / 2
        let cy = size / 2
        let R = size / 2 * 0.78
        let spin = o["spin"] ?? 1
        let camTilt = 0.3
        let pt = makeProj(yaw: t * 0.1 * spin, tilt: camTilt, cx: cx, cy: cy, scale: 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let ghostN = Int(o["ghostN"] ?? 150)
        for i in 0..<ghostN {
            let d = fibDir(Double(i), Double(ghostN))
            let (px, py, z) = pt(d.0 * R, d.1 * R, d.2 * R)
            let depth = (z / R + 1) / 2
            dots.append(OrbDot(x: px, y: py, z: z, r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth))
        }
        let faceOn = (o["faceOn"] ?? 0) != 0
        let ya = t * 0.24 * spin
        let ta = faceOn ? -camTilt : 0.55 + 0.3 * sin(t * 0.18) * spin
        let ux = cos(ya)
        let uy = 0.0
        let uz = sin(ya)
        let vx = -uz * sin(ta)
        let vy = cos(ta)
        let vz = ux * sin(ta)
        let nx = uy * vz - uz * vy
        let ny = uz * vx - ux * vz
        let nz = ux * vy - uy * vx
        let wobMul = o["wobMul"] ?? 1
        let wobAmp = 0.23 * wobMul
        let baseR = faceOn ? R / (1 + 0.85 * wobAmp) : R
        let baseLanes = o["lanes"] ?? 5
        let segs = Int(o["segs"] ?? 88)
        let lanes = Int(max(1, jsRound(baseLanes * (o["bandMul"] ?? 1))))
        let rBase = o["rBase"] ?? 1.1
        let rDepth = o["rDepth"] ?? 1.7
        for w in 0..<lanes {
            let fw = Double(w)
            let mid = Double(lanes - 1) / 2
            let laneOff = (fw - mid) * 0.075
            let edge = abs(fw - mid) / max(1, mid)
            for k in 0..<segs {
                let a = Double(k) / Double(segs) * 2 * Double.pi
                let wob = (0.16 * sin(a * 3 - t * 1.7 + fw * 0.22) + 0.07 * sin(a * 5 + t * 1.1)) * wobMul
                let radial = faceOn ? 1 + wob : 1
                let off = faceOn ? laneOff : laneOff + wob
                let x = ux * cos(a) + vx * sin(a) + nx * off
                let y = uy * cos(a) + vy * sin(a) + ny * off
                let z = uz * cos(a) + vz * sin(a) + nz * off
                let l = (x * x + y * y + z * z).squareRoot()
                let rr = baseR * radial
                let (px, py, zr) = pt(x / l * rr, y / l * rr, z / l * rr)
                let depth = (zr / R + 1) / 2
                dots.append(OrbDot(
                    x: px, y: py, z: zr,
                    r: (rBase + rDepth * depth) * (1 - 0.25 * edge) * rs,
                    white: 0.52 - 0.44 * depth + 0.18 * edge,
                    a: 0.4 + 0.6 * depth
                ))
            }
        }
        return finalizeFrame(dots, [], rMin: o["rMin"] ?? 0.3)
    }

    static func frameWeb(_ size: Double, _ t: Double, _ o: OrbOptions) -> OrbFrame {
        let cx = size / 2
        let cy = size / 2
        let R = size / 2 * 0.8 * (o["spread"] ?? 1)
        let pt = makeProj(yaw: t * 0.12, tilt: 0.32, cx: cx, cy: cy, scale: R)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        let nodeN = Int(o["nodeN"] ?? 30)
        let thr = o["thr"] ?? 0.72
        let nodeR = o["nodeR"] ?? 1.4
        let nodeRDepth = o["nodeRDepth"] ?? 1.8
        var nodes: [(Double, Double, Double)] = []
        nodes.reserveCapacity(nodeN)
        for i in 0..<nodeN {
            let fi = Double(i)
            let d = fibDir(fi, Double(nodeN))
            let x = d.0 + 0.3 * (vnoise(fi * 0.31 + 9, t * 0.24) - 0.5) * 2
            let y = d.1 + 0.3 * (vnoise(fi * 0.53 + 27, t * 0.21) - 0.5) * 2
            let z = d.2 + 0.3 * (vnoise(fi * 0.77 + 55, t * 0.27) - 0.5) * 2
            let l = (x * x + y * y + z * z).squareRoot()
            nodes.append((x / l, y / l, z / l))
        }
        var lines: [OrbLine] = []
        var dots: [OrbDot] = []
        for i in 0..<nodeN {
            for j in (i + 1)..<nodeN {
                let dx = nodes[i].0 - nodes[j].0
                let dy = nodes[i].1 - nodes[j].1
                let dz = nodes[i].2 - nodes[j].2
                let dist = (dx * dx + dy * dy + dz * dz).squareRoot()
                if dist >= thr { continue }
                let (x1, y1, z1) = pt(nodes[i].0, nodes[i].1, nodes[i].2)
                let (x2, y2, z2) = pt(nodes[j].0, nodes[j].1, nodes[j].2)
                let depth = ((z1 + z2) / 2 + 1) / 2
                lines.append(OrbLine(
                    x1: x1, y1: y1, x2: x2, y2: y2,
                    white: 0.42,
                    a: (1 - dist / thr) * (0.3 + 0.55 * depth),
                    w: max(0.6, (o["lineW"] ?? 0.8) * rs)
                ))
            }
        }
        for i in 0..<nodeN {
            let (px, py, z) = pt(nodes[i].0, nodes[i].1, nodes[i].2)
            let depth = (z + 1) / 2
            let pulse = 1 + 0.25 * sin(t * 1.4 + Double(i) * 2.7)
            dots.append(OrbDot(x: px, y: py, z: z, r: (nodeR + nodeRDepth * depth) * pulse * rs, white: 0.55 - 0.45 * depth))
        }
        let signals = Int(o["signals"] ?? 5)
        for s in 0..<signals {
            let fs = Double(s)
            let seg = floor(t * 0.55 + fs * 7.31)
            let a = Int(floor(hashD(seg, fs * 3.1 + 1.7) * Double(nodeN)))
            let b = Int(floor(hashD(seg, fs * 5.7 + 4.2) * Double(nodeN)))
            if a == b { continue }
            let f = frac(t * 0.55 + fs * 7.31)
            let x = lerp(nodes[a].0, nodes[b].0, f)
            let y = lerp(nodes[a].1, nodes[b].1, f)
            let z = lerp(nodes[a].2, nodes[b].2, f)
            let l = max(1e-6, (x * x + y * y + z * z).squareRoot())
            let (px, py, zr) = pt(x / l, y / l, z / l)
            let depth = (zr + 1) / 2
            dots.append(OrbDot(x: px, y: py, z: zr, r: (nodeR * 1.5 + nodeRDepth * depth) * rs, white: 0.05, a: 0.5 + 0.5 * depth))
        }
        return finalizeFrame(dots, lines, rMin: o["rMin"] ?? 0.3)
    }
}
