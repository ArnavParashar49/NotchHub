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


/// NEO's wake light — the quiet rim. While NEO listens, the island's own
/// edge lights: a one-pixel line of light lying ON the silhouette, with a
/// soft glow a few points into the black behind it, brightest along the
/// bottom and fading to nothing as the sides climb to the screen's top edge.
/// One broad highlight drifts slowly to and fro along it and the whole rim
/// breathes, barely. On waking, a single bright sweep runs from both top
/// ends to the bottom centre, blooms where it meets itself, and the bloom
/// becomes the drifting highlight. When listening ends it fades out in half
/// a second. The light's arithmetic is `NeoWakeLight`'s; `NeoWakeRim` draws
/// one moment of it.
///
/// WHERE THE LIGHT SITS: the line's inner edge is the silhouette — it is
/// the one device pixel just outside the black — and the glow is inside.
/// The island's black never grows; the line is light, not a border. It sits
/// outside because of the hardware: on every notch-height shape the
/// island's bottom edge IS the notch's, so anything drawn inside along it
/// would be hidden under the camera housing — and when the fox hides in the
/// notch, all of it would. Just outside, nothing ever covers it, so the line
/// is one even weight everywhere. The glow, which the notch would cover,
/// fades out before reaching it rather than being cut off by the housing's
/// corners.
///
/// GLUED TO THE ISLAND: this view fills the island's frame as the black
/// does (the same flexible frame in the same stack), so it knows the size
/// the black is really laid out at; `NeoWakeRim` animates that size, the
/// island's radii and the notch's place with the island's own transaction,
/// and draws every frame from those in-between values — so while the island
/// springs between shapes the light is drawn round exactly the black that
/// is on screen.
///
/// CHEAP: one `Canvas` — a dozen filled paths, four gradients — a frame;
/// no mask, no blur, no offscreen group. The timeline runs at the
/// display's own rate (120 Hz on ProMotion) through the wake and the exit,
/// eases to 60 Hz once the light has settled (`settledInterval` says why),
/// and is paused whenever nothing moves: while NEO is not listening, once
/// the exit has faded, while a context menu is open, offscreen, and — the
/// rim being still then — under Reduce Motion except during its fades.
struct NeoWakeOutlineView: View {
    let shape: NotchShape
    let isActive: Bool
    var paused = false
    /// The light's colour as RGB (the pet's glow setting,
    /// `PetSettings.glowColor`); `nil` is the design token's blue,
    /// `DesignTokens.wakeLight`.
    var tint: UInt32? = nil
    /// Offscreen rendering only (`--neo-outline-frames`): the moment to draw,
    /// in place of the timeline's clock — its `timeIntervalSinceReferenceDate`
    /// is the light's clock (seconds since the wake). `nil` — always, live —
    /// follows the display.
    var now: Date? = nil
    /// Offscreen rendering only: how far the light has come in, from 0 (dark)
    /// to 1 (settled), or gone out — `NeoWakeLight.activation`. `nil` live.
    /// An offscreen entrance passes `isActive` true with this rising; an exit
    /// passes `isActive` false with it falling, as the live view sees them.
    var activation: Double? = nil
    /// The physical notch in this view's coordinates (the island's), or
    /// `nil` when there is none to keep the glow off.
    var notch: CGRect? = nil
    /// Offscreen rendering only: Reduce Motion as if set (the environment's
    /// value is read-only). `nil` follows the system.
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// When this stretch of listening began: the light's clock starts here.
    @State private var wakeStart: Date?
    /// When it ended, while the light fades out.
    @State private var exitStart: Date?
    /// Whether the timeline is ticking: while listening (but for a still,
    /// Reduce Motion rim) and through the fades.
    @State private var running = false
    /// Whether the wake is over and the light has settled into its slow
    /// drift — when it no longer needs the display's full rate.
    @State private var settled = false

    /// The line: one device pixel on the Retina screens a notch comes on.
    static let hairline: CGFloat = 0.5
    /// The glow inside the line, as nested bands from the edge inward, each
    /// with its own opacity. They overlap, so the glow is brightest at the
    /// edge and falls away into the black — about 75, 48, 27, 12 and 5 % of
    /// the line's light in successive device pixels (the last ones two and
    /// three pixels deep) — and every band shares the silhouette as its
    /// outer edge, so no seam can show between them.
    static let glowBands: [(depth: CGFloat, alpha: Double)] = [(0.5, 0.519), (1, 0.288), (2, 0.171), (3.5, 0.074), (5, 0.05)]

    static var loopDuration: TimeInterval { NeoWakeLight.loopDuration }
    static var enterDuration: TimeInterval { NeoWakeLight.enterDuration }
    /// The exit's length (the light fades as its progress²).
    static var fadeDuration: TimeInterval { NeoWakeLight.exitDuration }

    /// Where the resting light is in its loop at `date` (0 ..< 1).
    static func cycle(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loopDuration) / loopDuration
        return t < 0 ? t + 1 : t
    }

    /// The live entrance/exit progress `seconds` after listening began
    /// (`appearing`) or ended — what the live view computes from its own
    /// clock, for offscreen renders of the same moments.
    static func liveActivation(seconds: TimeInterval, appearing: Bool) -> Double {
        NeoWakeLight.activation(seconds: seconds, appearing: appearing)
    }

    /// For `--neo-outline-morph`'s pacing probe: how many frames of light
    /// have been drawn, live.
    static var framesDrawn = 0

    /// The settled light's frame interval. The wake's sweep and the exit
    /// run at the display's full rate (120 Hz on ProMotion): the sweep's
    /// front is sharp and fast. Once settled, nothing on the rim has an edge
    /// and its fastest change — the highlight's flank as it swings — moves
    /// a pixel's brightness by under 1 % per 60 Hz frame, so a second
    /// 120 Hz frame in between would look identical and cost as much again
    /// (each frame re-renders the island's layer; measured with
    /// `--neo-outline-morph`). Springs between shapes are not bound by this:
    /// the island's animation draws the light at the display's rate.
    static let settledInterval: TimeInterval = 1.0 / 60

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    private var visible: Bool {
        if let activation { return isActive || activation > 0 }
        return isActive || running
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: settled ? Self.settledInterval : nil,
                                    paused: now != nil || paused || !running)) { context in
                NeoWakeRim(size: proxy.size, shape: shape, notch: notch,
                           phase: phase(at: now ?? context.date), tint: Self.components(tint))
            }
        }
        .opacity(visible ? 1 : 0)
        .onAppear {
            // Already listening when it appears (a relaunch): the settled
            // rim, without a wake.
            if isActive {
                running = !reduceMotion
                settled = true
            }
        }
        .onChange(of: isActive) { active in
            if active {
                wakeStart = Date()
                exitStart = nil
            } else {
                exitStart = Date()
            }
            running = true
            settled = false
        }
        // Eases the timeline down once the wake has settled, and stops it
        // once a fade is over and nothing moves.
        .task(id: FadeKey(active: isActive, reduceMotion: reduceMotion)) {
            if isActive, !reduceMotion {
                try? await Task.sleep(nanoseconds: UInt64((NeoWakeLight.enterDuration + 0.05) * 1_000_000_000))
                if !Task.isCancelled { settled = true }
                return
            }
            let fade = reduceMotion ? NeoWakeLight.reduceMotionFade : NeoWakeLight.exitDuration
            try? await Task.sleep(nanoseconds: UInt64((fade + 0.05) * 1_000_000_000))
            if !Task.isCancelled { running = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("NEO is listening")
        .accessibilityHidden(!isActive)
    }

    private struct FadeKey: Equatable {
        let active: Bool
        let reduceMotion: Bool
    }

    /// The light's phase at `date`: offscreen from the injected progress;
    /// live from when this stretch of listening began and ended.
    private func phase(at date: Date) -> NeoWakeLight.Phase {
        if now == nil { Self.framesDrawn += 1 }
        if let activation {
            return NeoWakeLight.phase(clock: date.timeIntervalSinceReferenceDate, activation: activation,
                                      listening: isActive, reduceMotion: reduceMotion)
        }
        if reduceMotion {
            let progress: Double
            if isActive {
                progress = wakeStart.map { NeoWakeLight.activation(seconds: date.timeIntervalSince($0), appearing: true, reduceMotion: true) } ?? 1
            } else {
                progress = exitStart.map { NeoWakeLight.activation(seconds: date.timeIntervalSince($0), appearing: false, reduceMotion: true) } ?? 0
            }
            return NeoWakeLight.phase(clock: 0, activation: progress, listening: isActive, reduceMotion: true)
        }
        let sinceWake = wakeStart.map { max(0, date.timeIntervalSince($0)) }
        let fade = isActive ? 1 : exitStart.map {
            NeoWakeLight.exitFade(remaining: NeoWakeLight.activation(seconds: date.timeIntervalSince($0), appearing: false))
        } ?? 0
        return NeoWakeLight.Phase(
            clock: sinceWake ?? date.timeIntervalSinceReferenceDate,
            wake: sinceWake.flatMap { $0 < NeoWakeLight.enterDuration ? $0 : nil },
            fade: fade
        )
    }

    /// The tint's sRGB components: the glow setting's, or the token's.
    static func components(_ rgb: UInt32?) -> (red: Double, green: Double, blue: Double) {
        guard let rgb else { return DesignTokens.wakeLightRGB }
        return (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
    }

    /// The rim's open contour at the silhouette itself: from the top-left
    /// end down the left side, round the bottom, and up to the top-right
    /// end, with nothing across the top.
    static func contour(_ shape: NotchShape, in rect: CGRect) -> Path {
        let rim = NotchRimGeometry(shape, in: rect)
        var path = Path()
        NotchRimGeometry.add(rim.half(.leading, offset: 0), to: &path, moving: true)
        NotchRimGeometry.add(rim.half(.trailing, offset: 0).reversed().map(\.reversed), to: &path, moving: false)
        return path
    }
}

/// One moment of NEO's wake light, drawn round the island as it is on
/// screen right now.
///
/// ANIMATABLE: its size, the island's four radii and the notch's place are
/// its animatable data, so when the island springs to a new shape SwiftUI
/// hands this view the in-between values on every frame of the spring — in
/// the same transaction as the black — and the paths AND the gradients are
/// computed from them together. (A shape's gradient fill resolves against
/// the view's laid-out frame, which jumps straight to the new size; a light
/// whose gradients followed that frame would slide along the rim mid-morph
/// and break at the bottom centre where its two halves meet.)
///
/// ONE CANVAS: everything is drawn in a single `Canvas` in absolute points
/// — the gradients' ends included — from just above and left of the
/// island's top-left (`margin`, so the line's ends at the flares are
/// inside it). One recorded drawing per frame, rendered on the GPU with the
/// rest of the island. Measured against the alternatives
/// (`--neo-outline-morph`): gradient-filled shapes are rasterised on the
/// CPU, layer by layer, at about twice the cost; gradient masks over a
/// fixed frame rasterise the whole frame. The GPU keeps its render cache
/// resident while the light animates (about 95 MB of graphics memory) and
/// gives it back within a couple of seconds of the light going out.
private struct NeoWakeRim: View, Animatable {
    var size: CGSize
    var shape: NotchShape
    var notch: CGRect?
    let phase: NeoWakeLight.Phase
    let tint: (red: Double, green: Double, blue: Double)

    /// How far the canvas reaches beyond the island on every side.
    static let margin: CGFloat = 8

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<NotchShape.AnimatableData, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(size.width, size.height),
                           AnimatablePair(shape.animatableData, notch?.minX ?? 0))
        }
        set {
            size = CGSize(width: newValue.first.first, height: newValue.first.second)
            shape.animatableData = newValue.second.first
            notch?.origin.x = newValue.second.second
        }
    }

    var body: some View {
        let m = Self.margin
        let island = CGRect(origin: CGPoint(x: m, y: m), size: size)
        let split = CGFloat(NeoWakeLight.split(size: size, notch: notch))
        // Everything this frame needs, computed here from the in-between
        // geometry and captured by the canvas.
        let halves: [(path: [Path], line: Path, glow: Gradient, lineGradient: Gradient, start: CGPoint, end: CGPoint)] =
            NeoWakeLight.Half.allCases.map { half in
                let stops = NeoWakeLight.stops(half: half, size: size, phase: phase, notch: notch)
                let axis = self.axis(half: half)
                let bands = NeoWakeOutlineView.glowBands.map {
                    NotchRimBand(shape: shape, island: island, half: half, split: split, inner: -$0.depth, outer: 0).path(in: .zero)
                }
                let line = NotchRimBand(shape: shape, island: island, half: half, split: split,
                                        inner: 0, outer: NeoWakeOutlineView.hairline).path(in: .zero)
                // The line leans to white where it is brightest (a hot
                // core); the glow keeps more of the tint, and keeps off the
                // notch.
                return (bands, line, gradient(stops, whiten: 0.35, glow: true), gradient(stops, whiten: 1), axis.start, axis.end)
            }
        return Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            for half in halves {
                for (index, band) in half.path.enumerated() {
                    var layer = context
                    layer.opacity = NeoWakeOutlineView.glowBands[index].alpha
                    layer.fill(band, with: .linearGradient(half.glow, startPoint: half.start, endPoint: half.end))
                }
                context.fill(half.line, with: .linearGradient(half.lineGradient, startPoint: half.start, endPoint: half.end))
            }
        }
        .frame(width: max(1, size.width) + m * 2, height: max(1, size.height) + m * 2)
        .offset(x: -m, y: -m)
    }

    /// One half's gradient axis, in the canvas's points: laid diagonally
    /// across its half of the island from the top end (`D` = 0) to the
    /// meeting point (`D` = 1) — the 45° axis whose projection is the
    /// Manhattan distance from the top end.
    private func axis(half: NeoWakeLight.Half) -> (start: CGPoint, end: CGPoint) {
        let width = max(1, size.width), m = Self.margin
        let reach = CGFloat(NeoWakeLight.reach(half: half, size: size, split: NeoWakeLight.split(size: size, notch: notch))) / 2
        return (CGPoint(x: m + (half == .leading ? 0 : width), y: m),
                CGPoint(x: m + (half == .leading ? reach : width - reach), y: m + reach))
    }

    /// A half's light as gradient stops in the tint. `glow`: for the glow,
    /// which keeps off the notch; not for the line.
    private func gradient(_ stops: [NeoWakeLight.Stop], whiten: Double, glow: Bool = false) -> Gradient {
        Gradient(stops: stops.map { stop in
            let w = stop.white * whiten
            return Gradient.Stop(
                color: Color(.sRGB, red: tint.red + (1 - tint.red) * w, green: tint.green + (1 - tint.green) * w,
                             blue: tint.blue + (1 - tint.blue) * w, opacity: stop.alpha * (glow ? stop.clear : 1)),
                location: stop.location
            )
        })
    }
}
