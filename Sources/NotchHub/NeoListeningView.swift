import NotchHubCore
import SwiftUI

/// NEO's listening glow: ONE pulse of light BEHIND the pet each time NEO
/// starts to listen, as if the fox pricked up and lit for a moment.
///
/// A blurred radial glow, the pet's size + 6 pt (22 pt around the 16-pt fox
/// of the notch strip), in `DesignTokens.listeningGlow`. It swells in, peaks
/// and fades fully out over 1.4 s — opacity 0 → 0.8 → 0 and scale
/// 0.88 → 1.06 → 0.88, eased up to the peak at 0.45 s and more slowly down
/// (`NeoListeningLayout.pulse`) — and then draws nothing for the rest of
/// that stretch of listening. NEO's core says THAT it is listening, not how
/// loud the room is, so the pulse claims no level. With Reduce Motion it is
/// a single soft fade in and out at its drawn size. It takes no room: the
/// island is exactly as wide as it is without it.
///
/// This is the island's one gradient, and deliberately so: it is light, not a
/// surface. A flat disc behind the fox would read as a badge; the radial
/// falloff and the blur are what make it a glow.
///
/// The view stays in the island behind the pet whether or not a pulse is
/// showing — drawing nothing, with its clock paused, while none is — so that
/// it travels with the pet's edge when the island springs. The pulse itself
/// is the arrival (it starts from dark), so nothing animates the mark coming
/// in; if listening ends mid-pulse the mark leaves early and what is lit
/// fades on a quick ease-out.
///
/// Drawn only: it takes no clicks and no hover (`IslandView` turns hit
/// testing off for its layer, and the window never routes a click to it).
struct NeoListeningGlowView: View {
    /// The pulse to show, or `nil` while there is none.
    let mark: NeoListeningMark?
    /// The pet's size in points (16 in the notch strip, 32 expanded).
    let petSize: CGFloat
    /// The light's colour: the design token's teal, or the one the user chose
    /// for their pet (`PetSettings.glow`).
    var tint: Color = DesignTokens.listeningGlow

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the last pulse began, so a pulse cut short keeps its place on the
    /// curve (rather than jumping) while it fades out.
    @State private var lastPulseStart: Date?

    private var shown: Bool { mark != nil }

    var body: some View {
        let diameter = NeoListeningLayout.glowDiameter(petSize: petSize)
        // Paused while no pulse shows: nothing is drawn, and nothing ticks.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !shown)) { context in
            let start = mark?.pulseStart ?? lastPulseStart ?? context.date
            let pulse = NeoListeningLayout.pulse(at: context.date.timeIntervalSince(start))
            halo(
                opacity: NeoListeningLayout.glowOpacity(pulse: pulse, reduceMotion: reduceMotion),
                scale: NeoListeningLayout.glowScale(pulse: pulse, reduceMotion: reduceMotion)
            )
        }
        .frame(width: diameter, height: diameter)
        // A pulse that ran its course is already dark when its mark goes; one
        // cut short (listening ended) fades from where it was.
        .opacity(shown ? 1 : 0)
        .animation(shown ? nil : DesignTokens.listeningGlowOut, value: shown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NeoListeningIndicator.accessibilityLabel)
        .accessibilityHidden(!shown)
        .onChange(of: mark?.pulseStart) { start in
            if let start { lastPulseStart = start }
        }
    }

    /// The light itself: full at the pet, falling away to nothing at the
    /// halo's edge, then blurred so no edge is left at all.
    private func halo(opacity: Double, scale: CGFloat) -> some View {
        let diameter = NeoListeningLayout.glowDiameter(petSize: petSize)
        return Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: tint, location: 0),
                    .init(color: tint, location: 0.55),
                    .init(color: tint.opacity(0.6), location: 0.8),
                    .init(color: tint.opacity(0), location: 1),
                ],
                center: .center, startRadius: 0, endRadius: diameter / 2
            ))
            .frame(width: diameter, height: diameter)
            .blur(radius: NeoListeningLayout.glowBlur * petSize / PetLayout.artSize)
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

/// NEO's wake cue: an open blue U that runs down both sides and around the
/// island's bottom, with its ends reaching the screen's top edge at both sides
/// but no stroke across the top. Two short beams travel in the same direction,
/// half a circuit apart, and wrap between the open ends. A narrow black
/// support stroke keeps the light visible against bright desktops. The island's
/// layout and centre do not change for the effect.
struct NeoWakeOutlineView: View {
    let shape: NotchShape
    let isActive: Bool
    var paused = false
    var tint: Color = DesignTokens.listeningGlow
    /// Offscreen rendering only (`--neo-outline-frames`): the moment to draw,
    /// in place of the timeline's clock, so a frame can be rendered at any
    /// time in the loop. `nil` — always, live — follows the display.
    var now: Date? = nil
    /// Offscreen rendering only: how far the light has come in, from 0 (dark)
    /// to 1 (fully lit), in place of the fade that `isActive` animates — so a
    /// frame of the light appearing or leaving can be drawn. `nil` live.
    /// An offscreen entrance passes `isActive` true with this rising; an exit
    /// passes `isActive` false with it falling, as the live view sees them.
    var activation: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Two points of black beyond the physical contour gives the blue edge a
    /// dark bed, without making the notch look meaningfully larger.
    static let supportInset: CGFloat = 2
    static let loopDuration: TimeInterval = 3.6
    static let beamLength: CGFloat = 0.115
    /// The fade `isActive` drives, in and out: `.easeOut(duration: fadeDuration)`.
    static let fadeDuration: TimeInterval = 0.18

    /// Where the beams are in their loop at `date` (0 ..< 1).
    static func cycle(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: loopDuration) / loopDuration
    }

    /// The live fade as an `activation`, `seconds` after `isActive` changed:
    /// what the eased opacity animation shows at that moment. For offscreen
    /// renders of the entrance (`appearing`) and the exit.
    static func liveActivation(seconds: TimeInterval, appearing: Bool) -> Double {
        let eased = easeOut(max(0, min(1, seconds / fadeDuration)))
        return appearing ? eased : 1 - eased
    }

    /// SwiftUI's `.easeOut` timing curve, the cubic Bézier (0, 0, 0.58, 1).
    static func easeOut(_ x: Double) -> Double {
        // Solve x(s) = x for the curve's parameter, then return y(s).
        func bezier(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
        }
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if bezier(mid, 0, 0.58) < x { lo = mid } else { hi = mid }
        }
        return bezier((lo + hi) / 2, 0, 1)
    }

    var body: some View {
        let frozen = now != nil
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: frozen || !isActive || paused || reduceMotion)) { context in
            GeometryReader { geometry in
                let physicalRect = CGRect(
                    x: Self.supportInset,
                    y: Self.supportInset,
                    width: geometry.size.width - Self.supportInset * 2,
                    height: geometry.size.height - Self.supportInset * 2
                )
                let path = Self.contour(shape, in: physicalRect)
                // The open contour is a circular track for the beams: they
                // flow left → down → right, then wrap to the left without
                // drawing across the deliberately clear top span.
                let cycle = Self.cycle(at: now ?? context.date)

                ZStack {
                    // Support only at the edge; this is not another filled badge.
                    path.stroke(Color.black, style: StrokeStyle(lineWidth: Self.supportInset * 2, lineCap: .round, lineJoin: .round))

                    if isActive {
                        path.stroke(tint.opacity(reduceMotion ? 0.78 : 0.56),
                                    style: StrokeStyle(lineWidth: reduceMotion ? 2.1 : 1.5, lineCap: .round, lineJoin: .round))

                        if !reduceMotion {
                            movingBeam(on: path, phase: cycle)
                            movingBeam(on: path, phase: (cycle + 0.5).truncatingRemainder(dividingBy: 1))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .opacity(activation ?? (isActive ? 1 : 0))
        .animation(activation == nil ? .easeOut(duration: Self.fadeDuration) : nil, value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("NEO is listening")
        .accessibilityHidden(!isActive)
    }

    /// The outline's open contour: from the top edge down the left side, around
    /// the bottom, and back up to the top on the right, without a stroke across
    /// the top edge itself.
    static func contour(_ shape: NotchShape, in rect: CGRect) -> Path {
        let handle: CGFloat = 0.4477
        let topLeft = max(0, min(shape.topLeadingRadius, rect.height / 2))
        let topRight = max(0, min(shape.topTrailingRadius, rect.height / 2))
        let bottomLeft = max(0, min(shape.bottomLeadingRadius, rect.width / 2, rect.height - topLeft))
        let bottomRight = max(0, min(shape.bottomTrailingRadius, rect.width / 2, rect.height - topRight))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX - topLeft, y: rect.minY))
        if topLeft > 0 {
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + topLeft),
                control1: CGPoint(x: rect.minX - topLeft * handle, y: rect.minY),
                control2: CGPoint(x: rect.minX, y: rect.minY + topLeft * handle)
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft))
        path.addCurve(
            to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft * handle),
            control2: CGPoint(x: rect.minX + bottomLeft * handle, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight),
            control1: CGPoint(x: rect.maxX - bottomRight * handle, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight * handle)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + topRight))
        if topRight > 0 {
            path.addCurve(
                to: CGPoint(x: rect.maxX + topRight, y: rect.minY),
                control1: CGPoint(x: rect.maxX, y: rect.minY + topRight * handle),
                control2: CGPoint(x: rect.maxX + topRight * handle, y: rect.minY)
            )
        }
        return path
    }

    /// A short, rounded beam and its soft blue trail. At the open ends, the
    /// beam wraps from one side to the other without crossing the top.
    private func movingBeam(on path: Path, phase: Double) -> some View {
        let end = phase + Double(Self.beamLength)
        var beamPath = Path()
        if end <= 1 {
            beamPath.addPath(path.trimmedPath(from: phase, to: end))
        } else {
            beamPath.addPath(path.trimmedPath(from: phase, to: 1))
            beamPath.addPath(path.trimmedPath(from: 0, to: end - 1))
        }
        return ZStack {
            beamPath.stroke(tint.opacity(0.28), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .blur(radius: 1.7)
            beamPath.stroke(tint.opacity(0.96), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }
}
