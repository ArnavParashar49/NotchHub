import NotchHubCore
import NotchHubOrbs
import SwiftUI

/// NEO's lane: its thinking orb and one line of text, at notch height.
///
/// `[inset][orb][gap][line][inset]` — see `NeoLaneLayout`. The orb is NEO's
/// own (the thinking-orbs engine, ported), light ink on the island's black.
/// A change of state crossfades the orb rather than cutting; the line swaps
/// without animating, so a streaming transcript never smears.
struct NeoLaneView: View {
    let content: NeoLaneContent
    /// The notch's height — the lane's height.
    let notchHeight: CGFloat
    /// The lane's width, from `NeoLaneLayout.width`.
    let width: CGFloat

    var body: some View {
        let orb = NeoLaneLayout.orbSize(notchHeight: notchHeight)
        let text = NeoLaneLayout.textWidth(notchHeight: notchHeight, laneWidth: width)
        HStack(spacing: NeoLaneLayout.gap) {
            ZStack {
                OrbView(state: content.state.orb, size: orb)
                    .id(content.state.orb)
                    .transition(.opacity)
            }
            .frame(width: orb, height: orb)
            .animation(.easeOut(duration: 0.25), value: content.state.orb)

            if text > 0 {
                Text(content.line)
                    .font(DesignTokens.compactFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                    // A transcript is read from its end: the latest words stay
                    // beside the orb while the start scrolls out of reach.
                    .truncationMode(content.isTranscript ? .head : .tail)
                    .frame(width: text, alignment: content.isTranscript ? .trailing : .leading)
                    .transaction { $0.animation = nil }
            }
        }
        .padding(.leading, NeoLaneLayout.outerInset)
        .padding(.trailing, NeoLaneLayout.innerInset)
        .frame(width: width, height: notchHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("NEO: \(content.line)")
    }
}
