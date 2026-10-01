import SwiftUI

/// One of NEO's thinking orbs, drawn with `OrbEngine` on a SwiftUI `Canvas`.
///
/// The painter is the JS one: lines first, then the z-sorted dots as plain
/// filled circles, with the ink mirrored on a dark substrate so near dots read
/// bright. No blur, no glow — the same pixels the web canvas draws. The view
/// redraws on the display's own cadence through `TimelineView(.animation)` and
/// every orb shares one clock, so instances stay in phase.
public struct OrbView: View {
    /// Which animation to show.
    public var state: OrbState
    /// Rendered size in points. The geometry is drawn at this size; the tuning
    /// (dot count, dot size, speed) comes from `preset`.
    public var size: CGFloat
    /// Which tuned design to draw with. Defaults to the one nearest `size`.
    public var preset: OrbSizePreset?
    /// Multiplier on the preset's baked speed.
    public var speed: Double = 1
    /// Light ink for a dark substrate (the island), dark ink otherwise.
    public var dark: Bool = true
    /// Freeze on the current frame.
    public var paused: Bool = false
    /// How the marks are boosted for a tiny rendering — see `OrbEmphasis`.
    /// `nil` paints exactly what the engine emitted.
    public var emphasis: OrbEmphasis? = nil

    public init(state: OrbState, size: CGFloat, preset: OrbSizePreset? = nil, speed: Double = 1, dark: Bool = true, paused: Bool = false, emphasis: OrbEmphasis? = nil) {
        self.state = state
        self.size = size
        self.preset = preset
        self.speed = speed
        self.dark = dark
        self.paused = paused
        self.emphasis = emphasis
    }

    /// The clock every orb reads, so a state change never restarts the motion
    /// and several orbs on screen move together.
    static let epoch = Date()

    public var body: some View {
        let resolved = OrbEngine.resolvePreset(state: state, size: preset ?? .nearest(to: Double(size)))
        let effectiveSpeed = resolved.speed * speed
        TimelineView(.animation(paused: paused)) { context in
            let t = context.date.timeIntervalSince(Self.epoch) * effectiveSpeed
            Canvas(opaque: false, rendersAsynchronously: false) { graphics, _ in
                let frame = OrbEngine.frame(mode: resolved.mode, size: Double(size), t: t, opts: resolved.opts)
                Self.paint(frame, dark: dark, emphasis: emphasis, in: &graphics)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Self.label(for: state))
    }

    /// Paints a finished frame: lines, then dots on top. With an `emphasis`
    /// the marks are boosted first (`OrbEmphasis.apply`), so a 28 pt orb on
    /// a black bar reads as an orb and not as a scatter of faint specks.
    public static func paint(_ frame: OrbFrame, dark: Bool, emphasis: OrbEmphasis? = nil, in context: inout GraphicsContext) {
        let frame = emphasis.map { $0.apply(to: frame, dark: dark) } ?? frame
        for line in frame.lines {
            var path = Path()
            path.move(to: CGPoint(x: line.x1, y: line.y1))
            path.addLine(to: CGPoint(x: line.x2, y: line.y2))
            context.stroke(path, with: .color(ink(line.white, alpha: line.a, dark: dark)), lineWidth: line.w)
        }
        for dot in frame.dots {
            let rect = CGRect(x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(ink(dot.white, alpha: dot.a, dark: dark)))
        }
    }

    /// The JS `inkColor`: a grey from the ink value, mirrored on dark, rounded
    /// to 8 bits exactly as `rgba()` is.
    static func ink(_ white: Double, alpha: Double, dark: Bool) -> Color {
        let level = inkLevel(white, dark: dark)
        return Color(.sRGB, red: level, green: level, blue: level, opacity: alpha)
    }

    /// The grey level (0…1) for an ink value, as the JS `inkColor` computes
    /// its 8-bit channel.
    public static func inkLevel(_ white: Double, dark: Bool) -> Double {
        let w = min(1, max(0, white))
        let g = (dark ? 1 - w : w) * 255
        return g.rounded() / 255
    }

    static func label(for state: OrbState) -> String {
        switch state {
        case .working: return "Working…"
        case .searching: return "Searching…"
        case .solving: return "Solving…"
        case .listening: return "Listening…"
        case .connecting: return "Connecting…"
        case .weaving: return "Weaving…"
        case .composing: return "Composing…"
        case .breathing: return "Thinking…"
        case .shaping: return "Shaping…"
        }
    }
}

/// How a tiny orb is boosted so it still reads as an orb.
///
/// The engine's presets are tuned for 64 pt and up: at notch height the
/// 64-pt design scaled down keeps the orb's SHAPE (its rings, its web, its
/// braid — the sparse 20/32-pt designs lose it) but its dots shrink below a
/// pixel and its far side fades to a grey that is invisible on black. The
/// emphasis is applied to the finished frame, never to the geometry: every
/// dot grows by `dotScale` and to at least `dotFloor`, every line widens by
/// `lineScale`, and the ink is lifted so the nearest marks reach `inkPeak`
/// and even the farthest stay above `inkFloor`, with `alphaGain` on top.
/// The engine's golden frames are untouched: this is paint, not geometry.
public struct OrbEmphasis: Equatable, Sendable {
    public var dotScale: Double
    public var dotFloor: Double
    public var lineScale: Double
    /// The brightest grey level (0…1) the ink reaches, for the nearest dots.
    public var inkPeak: Double
    /// The dimmest grey level the ink is allowed to fall to.
    public var inkFloor: Double
    public var alphaGain: Double

    public init(dotScale: Double, dotFloor: Double, lineScale: Double, inkPeak: Double, inkFloor: Double, alphaGain: Double) {
        self.dotScale = dotScale
        self.dotFloor = dotFloor
        self.lineScale = lineScale
        self.inkPeak = inkPeak
        self.inkFloor = inkFloor
        self.alphaGain = alphaGain
    }

    /// The tuning for NEO's lane: the 64-pt design at 28 pt on the island's
    /// black, with white (~0.95) ink and dots a touch thicker.
    public static let notch = OrbEmphasis(dotScale: 1.35, dotFloor: 0.85, lineScale: 1.5, inkPeak: 0.95, inkFloor: 0.42, alphaGain: 1.25)

    /// Lifts the marks of a finished frame. `dark` says which way the ink
    /// values read (see `OrbView.inkLevel`); the result's `white` values are
    /// rewritten so `OrbView.ink` paints the lifted grey.
    public func apply(to frame: OrbFrame, dark: Bool) -> OrbFrame {
        var out = frame
        for i in out.dots.indices {
            out.dots[i].r = max(dotFloor, out.dots[i].r * dotScale)
            out.dots[i].white = lift(out.dots[i].white, dark: dark)
            out.dots[i].a = min(1, out.dots[i].a * alphaGain)
        }
        for i in out.lines.indices {
            out.lines[i].w *= lineScale
            out.lines[i].white = lift(out.lines[i].white, dark: dark)
            out.lines[i].a = min(1, out.lines[i].a * alphaGain)
        }
        return out
    }

    /// Maps an ink value so its grey level lands in `inkFloor…inkPeak`,
    /// keeping the far-to-near gradient. Returned as an ink value again.
    func lift(_ white: Double, dark: Bool) -> Double {
        let level = OrbView.inkLevel(white, dark: dark)
        let lifted = inkFloor + (inkPeak - inkFloor) * level
        return dark ? 1 - lifted : lifted
    }
}
