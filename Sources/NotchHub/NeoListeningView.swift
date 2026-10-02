import NotchHubCore
import SwiftUI

/// NEO's listening glow: a soft halo that breathes BEHIND the pet while NEO's
/// microphone is live, as if the fox were lit up and paying attention.
///
/// A blurred radial glow, the pet's size + 6 pt (22 pt around the 16-pt fox
/// of the notch strip), in `DesignTokens.listeningGlow`. It breathes slowly —
/// opacity 0.35 ↔ 0.75 and scale 0.92 ↔ 1.06 on a 1.6 s sine
/// (`NeoListeningLayout.breath`) — to its own rhythm: NEO's core says THAT it
/// is listening, not how loud the room is, so the glow claims no level. With
/// Reduce Motion it is steady. It takes no room: the island is exactly as
/// wide as it is without it.
///
/// This is the island's one gradient, and deliberately so: it is light, not a
/// surface. A flat disc behind the fox would read as a badge; the radial
/// falloff and the blur are what make it a glow.
///
/// The view stays in the island behind the pet whether or not NEO is
/// listening — drawing nothing, with its clock paused, while it is not — so
/// that it travels with the pet's edge when the island springs. It comes up
/// on its own soft spring when listening starts and fades when it ends (the
/// island's frame often does not change with it, so it cannot borrow the
/// island's transaction).
///
/// Drawn only: it takes no clicks and no hover (`IslandView` turns hit
/// testing off for its layer, and the window never routes a click to it).
struct NeoListeningGlowView: View {
    /// The mark to show, or `nil` while NEO is not listening.
    let mark: NeoListeningMark?
    /// The pet's size in points (16 in the notch strip, 32 expanded).
    let petSize: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the last stretch of listening began, so the glow keeps its breath
    /// (rather than jumping) while it fades out.
    @State private var lastSince: Date?

    private var shown: Bool { mark != nil }

    var body: some View {
        let diameter = NeoListeningLayout.glowDiameter(petSize: petSize)
        Group {
            if reduceMotion {
                halo(opacity: NeoListeningLayout.steadyOpacity, scale: NeoListeningLayout.steadyScale)
            } else {
                // Paused while NEO is not listening: nothing is drawn, and
                // nothing ticks.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shown)) { context in
                    let since = mark?.since ?? lastSince ?? context.date
                    let breath = NeoListeningLayout.breath(at: context.date.timeIntervalSince(since))
                    halo(opacity: NeoListeningLayout.glowOpacity(breath: breath), scale: NeoListeningLayout.glowScale(breath: breath))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        // Lit and unlit: the halo swells out from behind the pet on its own
        // spring, and fades back into it.
        .scaleEffect(shown ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .animation(shown ? DesignTokens.listeningGlowIn : DesignTokens.listeningGlowOut, value: shown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NeoListeningIndicator.accessibilityLabel)
        .accessibilityHidden(!shown)
        .onChange(of: mark?.since) { since in
            if let since { lastSince = since }
        }
    }

    /// The light itself: full at the pet, falling away to nothing at the
    /// halo's edge, then blurred so no edge is left at all.
    private func halo(opacity: Double, scale: CGFloat) -> some View {
        let diameter = NeoListeningLayout.glowDiameter(petSize: petSize)
        let tint = DesignTokens.listeningGlow
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

/// The word "Listening", beside the pet for the first 1.5 s of each stretch
/// of listening — on the pet's inner side, toward the notch.
///
/// Like the glow it stays in the island (drawing nothing) so that it travels
/// with the pet's edge; the word arrives once the island has started to make
/// room and leaves quickly, before the island has closed over it — the
/// island's own rule for content. Its place is a fixed-width slot; only the
/// fade inside it keeps its own timing. Decoration for assistive technology:
/// the glow carries "Neo is listening".
struct NeoListeningLabelView: View {
    /// The mark to show, or `nil` while NEO is not listening.
    let mark: NeoListeningMark?
    /// On the left of the notch the word stands on the pet's right — still
    /// toward the notch.
    var mirrored = false

    private var showsLabel: Bool { mark?.showsLabel ?? false }

    var body: some View {
        Color.clear
            .frame(width: min(IslandMetrics.listeningLabelWidth, NeoListeningLayout.maxLabelWidth), height: NeoListeningLayout.labelHeight)
            .overlay(alignment: mirrored ? .leading : .trailing) {
                Text(NeoListeningIndicator.label)
                    .font(DesignTokens.compactFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(showsLabel ? 1 : 0)
                    .animation(showsLabel ? DesignTokens.contentIn : DesignTokens.contentOut, value: showsLabel)
            }
            .accessibilityHidden(true)
    }
}
