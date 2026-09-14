import NotchHubCore
import SwiftUI

/// The sideways hover peek: a notch-height bar with a wing on each side.
///
/// The left wing is the frontmost app's identity — its real icon, plus its
/// name, site, model or window title when the app has a strip. The right wing
/// is either live status (charging, music, Wi-Fi, weather), a browser's back /
/// forward / new-tab buttons, or a coding agent's token count.
///
/// Each wing is as wide as its own content, like the compact bar; the middle
/// sits behind the physical notch.
struct WingView: View {
    /// What the two wings show.
    let status: WingStatus
    /// The notch's width — the gap the wings leave in the middle.
    let notchWidth: CGFloat
    /// The notch's height, which is also the bar's height.
    let notchHeight: CGFloat
    /// Room kept free at the right end of the right wing (the pixel pet).
    var trailingReserve: CGFloat = 0
    /// The left wing's width; `nil` splits the bar evenly.
    var leadWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: 0) {
            if let leadWidth {
                leftWing.frame(width: leadWidth)
            } else {
                leftWing.frame(maxWidth: .infinity)
            }

            // The notch cutout itself — nothing is visible here.
            Color.clear.frame(width: notchWidth)

            rightWing
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left

    private var leftWing: some View {
        HStack(spacing: 0) {
            if let left = status.left {
                wingItem(left, size: DesignTokens.iconSizeWingApp)
            }
            if let strip = status.strip {
                Text(strip.label)
                    .font(DesignTokens.compactFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: IslandMetrics.stripLabelMaxWidth, alignment: .leading)
                    .padding(.leading, status.left == nil ? 0 : IslandMetrics.stripLabelSpacing)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, DesignTokens.wingInset)
    }

    // MARK: - Right

    @ViewBuilder
    private var rightWing: some View {
        switch status.strip?.trailing {
        case .browserControls?:
            browserControls
        case let .agent(tokens, isWorking)?:
            agentReadout(tokens: tokens, isWorking: isWorking)
        case .status?, nil:
            statusItems
        }
    }

    private var statusItems: some View {
        HStack(spacing: DesignTokens.space8) {
            Spacer().frame(width: DesignTokens.wingInset)
            if status.musicPlaying {
                MusicVisualizer(isPlaying: true)
            }
            ForEach(Array(status.right.enumerated()), id: \.offset) { _, item in
                wingItem(item, size: DesignTokens.iconSizeWingStatus)
            }
            Spacer(minLength: 0)
        }
    }

    /// Back, forward, new tab — one capsule at the trailing edge, where
    /// `WingControlLayout` hit-tests each segment.
    private var browserControls: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: WingControlLayout.spacing) {
                ForEach(Array(WingControlLayout.controls.enumerated()), id: \.offset) { _, action in
                    Image(systemName: Self.symbol(for: action))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(width: WingControlLayout.buttonSize, height: WingControlLayout.buttonSize)
                }
            }
            .background(Capsule().fill(DesignTokens.controlClusterFill))
            .overlay(Capsule().strokeBorder(DesignTokens.controlClusterStroke, lineWidth: 0.5))
        }
        .padding(.trailing, DesignTokens.wingInset + trailingReserve)
    }

    private func agentReadout(tokens: String, isWorking: Bool) -> some View {
        HStack(spacing: IslandMetrics.agentSpacing) {
            Spacer(minLength: 0)
            Image(systemName: "flame.fill")
                .font(.system(size: IslandMetrics.agentGlyphWidth, weight: .semibold))
                .foregroundStyle(isWorking ? DesignTokens.warning : DesignTokens.textTertiary)
            Text(tokens)
                .font(DesignTokens.compactFont)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
        }
        .padding(.trailing, DesignTokens.wingInset + trailingReserve)
    }

    static func symbol(for action: BrowserAction) -> String {
        switch action {
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .reload: return "arrow.clockwise"
        case .newTab: return "plus"
        case .selectTab: return "square.on.square"
        }
    }

    // MARK: - Glyphs

    /// One wing glyph: a real app icon when the item carries one, otherwise an
    /// SF Symbol tinted by the item's intent.
    @ViewBuilder
    private func wingItem(_ item: WingItem, size: CGFloat) -> some View {
        if let data = item.iconData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color(for: item.tint))
        }
    }

    private func color(for tint: WingTint) -> Color {
        switch tint {
        case .normal: return DesignTokens.textPrimary
        case .accent: return DesignTokens.accent
        case .warning: return DesignTokens.warning
        case .live: return DesignTokens.live
        }
    }
}
