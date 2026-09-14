import NotchHubCore
import SwiftUI

/// The frontmost-app skin: a compact identity strip.
///
/// The app's symbol sits in a small rounded chip on the left, its name is the
/// primary line, and its live state or detail is the quiet second line — like
/// a menu-bar app identity, but living in the island.
struct SkinView: View {
    let skin: AppSkin

    var body: some View {
        HStack(spacing: DesignTokens.space12) {
            Image(systemName: skin.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: 34, height: 34)
                .background(
                    DesignTokens.chipFill,
                    in: Rectangle()
                )

            VStack(alignment: .leading, spacing: DesignTokens.space2) {
                Text(skin.name)
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                if let state = skin.state {
                    Text(state)
                        .font(DesignTokens.subtitleFont)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                } else if let detail = skin.detail {
                    Text(detail)
                        .font(DesignTokens.subtitleFont)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
