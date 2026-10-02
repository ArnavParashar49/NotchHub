import NotchHubCore
import SwiftUI

/// NEO needs an OK: Allow and Cancel, one row under the notch, and nothing
/// else — no title, no words about the action (NEO says it, once; assistive
/// technology reads it from the surface's label), no chat.
///
/// The buttons are DRAWN, placed by `NeoConfirmLayout`, which the window
/// also hit-tests clicks against: the island takes no key focus to show
/// them, so a click is routed by position rather than by SwiftUI — and so
/// lands the first time, in a window that is not key. Allow is the white
/// capsule; Cancel the quiet one. The one the cursor rests on lifts.
struct NeoConfirmView: View {
    let card: NeoConfirmCard
    /// The button the cursor is on, as the coordinator resolved it.
    var hovered: NeoConfirmChoice? = nil
    /// For assistive technology, which presses a button without a click.
    var onChoice: (NeoConfirmChoice) -> Void = { _ in }

    var body: some View {
        HStack(spacing: NeoConfirmLayout.spacing) {
            ForEach(NeoConfirmLayout.order, id: \.self) { choice in
                button(choice)
            }
        }
        .padding(.horizontal, NeoConfirmLayout.horizontalInset)
        .padding(.top, NeoConfirmLayout.topGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(DesignTokens.hoverTint, value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.announcement)
    }

    private func button(_ choice: NeoConfirmChoice) -> some View {
        let primary = choice == .allow
        let isHovered = hovered == choice
        let fill: Color = primary
            ? (isHovered ? DesignTokens.confirmPrimaryFillHover : DesignTokens.controlPrimaryFill)
            : (isHovered ? DesignTokens.confirmSecondaryFillHover : DesignTokens.confirmSecondaryFill)
        return Text(choice.title)
            .font(DesignTokens.titleFont)
            .foregroundStyle(primary ? DesignTokens.controlPrimaryGlyph : DesignTokens.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: NeoConfirmLayout.buttonHeight)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
            .accessibilityElement()
            .accessibilityLabel(choice.title)
            .accessibilityHint(card.summary)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onChoice(choice) }
    }
}
