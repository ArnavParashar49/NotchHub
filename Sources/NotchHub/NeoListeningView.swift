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
    static var hairline: CGFloat { CGFloat(NeoWakeLight.hairline) }

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
                           phase: phase(at: now ?? context.date), tint: Self.components(tint), offscreen: now != nil)
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
/// ONE CANVAS, back to front, in absolute points from just above and left
/// of the island's top-left (`margin`), each part one gradient per half of
/// the rim (`NeoWakeLight.stops`) in its own colour of the palette:
///
/// 1. the HAZE — the atmosphere: each half of the island, grown a few
///    points, filled with its light in the palette's deep blue, blurred (a
///    true Gaussian) and clipped to OUTSIDE the island. What is left is the
///    blur's soft shoulder beyond the silhouette: light bleeding out into
///    the desktop like the air over a horizon seen from orbit, strongest at
///    the line and fading smoothly to nothing. The clip is what keeps it
///    off the black — the island never grows, never darkens. At rest the
///    blur is a mask made once per island shape (`NeoWakeHaze`) that the
///    light along the rim is multiplied by — a blur pass every frame cost
///    a third more than design C's whole light; with the mask the settled
///    light costs what C's did (`--neo-outline-morph`: about 2.4 M
///    instructions a frame). While the island springs, every frame is a
///    new shape, and during the 1.5 s wake the sweep's sharp front needs
///    the blur to soften it, so then the light is blurred on the GPU
///    (handing over to the mask as the wake ends: `NeoWakeLight.hazeMasked`).
/// 2. the NEAR GLOW — a narrow saturated band hugging the line outside,
///    and 3. the RIM LIGHT just inside the black (kept off the hardware
///    notch): both a Gaussian falloff laid down one device pixel per row
///    (`NeoWakeLight.nearProfile`, `.innerProfile`) as nested bands that all
///    share the silhouette as one edge — at pixel scale, a row per pixel is
///    the smooth curve itself, with no blur pass to pay for;
/// 4. the LINE — crisp, one device pixel, its inner edge the silhouette.
private struct NeoWakeRim: View, Animatable {
    var size: CGSize
    var shape: NotchShape
    var notch: CGRect?
    let phase: NeoWakeLight.Phase
    let tint: (red: Double, green: Double, blue: Double)
    /// Rendered offscreen (`--neo-outline-frames`): the island never moves,
    /// so the haze's mask is made at once.
    var offscreen = false

    @Environment(\.displayScale) private var displayScale

    /// How far the canvas reaches beyond the island on every side: past
    /// where the haze has faded out (`NeoWakeLight.glowReach`), so the blur
    /// is never cut by the canvas's edge.
    static let margin: CGFloat = CGFloat(NeoWakeLight.glowReach).rounded(.up) + 2
    /// The nested bands' opacities, outside (the near glow) and inside.
    static let nearAlphas = NeoWakeLight.nestedAlphas(NeoWakeLight.nearProfile)
    static let innerAlphas = NeoWakeLight.nestedAlphas(NeoWakeLight.innerProfile)

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

    /// One half's drawing for this frame.
    private struct Half {
        /// The haze's source: the island's half, flare to meeting point,
        /// grown `hazeLift` to be blurred, or as far as the haze reaches to
        /// be masked — each only when this frame draws it.
        let blurSource: Path?
        let maskSource: Path?
        /// The near glow's and the rim light's nested bands, from the
        /// narrowest out (or in).
        let near: [Path]
        let inner: [Path]
        let line: Path
        let hazeGradient: Gradient
        let nearGradient: Gradient
        let innerGradient: Gradient
        let lineGradient: Gradient
        let start: CGPoint
        let end: CGPoint
    }

    var body: some View {
        let m = Self.margin
        let island = CGRect(origin: CGPoint(x: m, y: m), size: size)
        let split = CGFloat(NeoWakeLight.split(size: size, notch: notch))
        let palette = Self.palette(NeoWakeLight.Colour(tint))
        let rim = NotchRimGeometry(shape, in: island)
        let row = NeoWakeOutlineView.hairline
        let canvas = CGSize(width: max(1, size.width) + m * 2, height: max(1, size.height) + m * 2)
        // The haze's shape, once the island holds still (see `NeoWakeHaze`)
        // — but not during the wake's sweep (`NeoWakeLight.hazeMasked`): the
        // masked haze takes its light from the rim along the gradients' 45°
        // axes, undiffused, so the sweep's sharp front would cast a hard
        // dark wedge into the haze under the meeting point; blurred, the
        // light itself is softened with it, as the haze of a horizon is.
        let masked = NeoWakeLight.hazeMasked(phase)
        let mask = masked > 0
            ? NeoWakeHaze.mask(for: NeoWakeHaze.Key(canvas: canvas, island: island, shape: shape, scale: displayScale),
                               shape: shape, always: offscreen)
            : nil
        // The share drawn from the mask; the rest is blurred.
        let maskWeight = mask == nil ? 0 : masked
        // Everything this frame needs, computed here from the in-between
        // geometry and captured by the canvas.
        let halves: [Half] = NeoWakeLight.Half.allCases.map { half in
            let stops = NeoWakeLight.stops(half: half, size: size, phase: phase, notch: notch)
            let axis = self.axis(half: half)
            func band(_ inner: CGFloat, _ outer: CGFloat) -> Path {
                NotchRimBand(shape: shape, island: island, half: half, split: split, inner: inner, outer: outer).path(in: .zero)
            }
            return Half(
                // Blurred, the haze's light is the island grown by the lift;
                // masked, it covers all the haze can reach.
                blurSource: maskWeight < 1
                    ? NeoWakeHaze.region(rim, half: half, split: split, grown: CGFloat(NeoWakeLight.hazeLift)) : nil,
                maskSource: maskWeight > 0
                    ? NeoWakeHaze.region(rim, half: half, split: split, grown: CGFloat(NeoWakeLight.glowReach + 1)) : nil,
                near: Self.nearAlphas.indices.map { band(0, row * CGFloat($0 + 2)) },
                inner: Self.innerAlphas.indices.map { band(-row * CGFloat($0 + 1), 0) },
                line: band(0, row),
                // The haze on its own fixed grid (`NeoWakeLight.hazeStops`),
                // so it never steps when the wake ends.
                hazeGradient: gradient(NeoWakeLight.hazeStops(half: half, size: size, phase: phase, notch: notch),
                                       colour: palette.haze, level: NeoWakeLight.hazeLevel),
                nearGradient: gradient(stops, colour: palette.near, level: 1),
                innerGradient: gradient(stops, colour: palette.inner, level: 1, keepOffNotch: true),
                lineGradient: gradient(stops, colour: palette.line, level: NeoWakeLight.lineLevel, whiten: true),
                start: axis.start, end: axis.end
            )
        }
        let silhouette = shape.path(in: island)
        return Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            func shade(_ gradient: Gradient, _ half: Half) -> GraphicsContext.Shading {
                .linearGradient(gradient, startPoint: half.start, endPoint: half.end)
            }
            // The haze, outside the island.
            var outside = context
            outside.clip(to: silhouette, options: .inverse)
            if maskWeight < 1 {
                // Springing, or waking: the light, blurred on the GPU.
                var blurred = outside
                blurred.opacity = 1 - maskWeight
                blurred.drawLayer { layer in
                    layer.addFilter(.blur(radius: CGFloat(NeoWakeLight.hazeRadius)))
                    for half in halves { if let source = half.blurSource { layer.fill(source, with: shade(half.hazeGradient, half)) } }
                }
            }
            if let mask, maskWeight > 0 {
                // At rest: the light along the rim, times the haze's shape
                // (drawn pixel for pixel, at the size it was made).
                var masking = outside
                masking.opacity = maskWeight
                masking.drawLayer { layer in
                    for half in halves { if let source = half.maskSource { layer.fill(source, with: shade(half.hazeGradient, half)) } }
                    layer.blendMode = .destinationIn
                    layer.draw(Image(decorative: mask, scale: displayScale),
                               in: CGRect(x: 0, y: 0, width: CGFloat(mask.width) / displayScale, height: CGFloat(mask.height) / displayScale))
                }
            }
            for half in halves {
                // The near glow over it, and the rim light inside.
                for (band, alpha) in zip(half.near, Self.nearAlphas) {
                    var layer = context
                    layer.opacity = alpha
                    layer.fill(band, with: shade(half.nearGradient, half))
                }
                for (band, alpha) in zip(half.inner, Self.innerAlphas) {
                    var layer = context
                    layer.opacity = alpha
                    layer.fill(band, with: shade(half.innerGradient, half))
                }
                // The line, crisp, on top.
                context.fill(half.line, with: shade(half.lineGradient, half))
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .offset(x: -m, y: -m)
    }

    /// The palette for a tint, kept for the next frame: a tint changes only
    /// when the user picks another glow colour.
    private static var lastPalette: (tint: NeoWakeLight.Colour, palette: NeoWakeLight.Palette)?
    static func palette(_ tint: NeoWakeLight.Colour) -> NeoWakeLight.Palette {
        if let last = lastPalette, last.tint == tint { return last.palette }
        let palette = NeoWakeLight.palette(tint: tint)
        lastPalette = (tint, palette)
        return palette
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

    /// A half's light as gradient stops in `colour` at `level` × its
    /// brightness. `keepOffNotch`: for the rim light inside, which the
    /// hardware notch would cover. `whiten`: for the line, which pales a
    /// little at its hottest (`Stop.white`, at most `NeoWakeLight.maxWhite`).
    private func gradient(_ stops: [NeoWakeLight.Stop], colour: NeoWakeLight.Colour, level: Double,
                          keepOffNotch: Bool = false, whiten: Bool = false) -> Gradient {
        Gradient(stops: stops.map { stop in
            let c = whiten ? colour.whitened(stop.white) : colour
            return Gradient.Stop(
                color: Color(.sRGB, red: c.red, green: c.green, blue: c.blue,
                             opacity: min(1, stop.alpha * level * (keepOffNotch ? stop.clear : 1))),
                location: stop.location
            )
        })
    }
}
