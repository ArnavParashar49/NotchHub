import NotchHubCore
import NotchHubOrbs
import SwiftUI

/// NEO's lane: its thinking orb, alone, at notch height.
///
/// `[inset][orb][inset]` — see `NeoLaneLayout`. The orb is NEO's own (the
/// thinking-orbs engine, ported), light ink on the island's black: the 64-pt
/// design drawn at notch height with `OrbEmphasis.notch`, so it keeps its
/// shape and reads as a bright orb rather than a few faint specks. A change
/// of state crossfades the orb rather than cutting. No words: what NEO hears
/// and says is the panel's to show; the lane only says that NEO is busy.
struct NeoLaneView: View {
    let content: NeoLaneContent
    /// The notch's height — the lane's height.
    let notchHeight: CGFloat
    /// The lane's width, from `NeoLaneLayout.width` (or `fitted`).
    let width: CGFloat

    var body: some View {
        let orb = NeoLaneLayout.orbSize(notchHeight: notchHeight)
        ZStack {
            OrbView(state: content.state.orb, size: orb, preset: .large, emphasis: .notch)
                .id(content.state.orb)
                .transition(.opacity)
        }
        .frame(width: orb, height: orb)
        .animation(.easeOut(duration: 0.25), value: content.state.orb)
        .padding(.leading, NeoLaneLayout.outerInset)
        .frame(width: width, height: notchHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("NEO: \(content.line)")
    }
}
