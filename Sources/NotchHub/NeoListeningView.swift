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
