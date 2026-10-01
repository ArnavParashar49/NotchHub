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

    public init(state: OrbState, size: CGFloat, preset: OrbSizePreset? = nil, speed: Double = 1, dark: Bool = true, paused: Bool = false) {
        self.state = state
        self.size = size
        self.preset = preset
        self.speed = speed
        self.dark = dark
        self.paused = paused
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
                Self.paint(frame, dark: dark, in: &graphics)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Self.label(for: state))
    }

    /// Paints a finished frame: lines, then dots on top.
    public static func paint(_ frame: OrbFrame, dark: Bool, in context: inout GraphicsContext) {
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
