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
    /// Room at the outer end of the left wing that is not the wing's (NEO's
    /// lane): its content starts past it.
    var leadInset: CGFloat = 0
    /// The control the cursor is resting on, resolved by the coordinator against
    /// `WingControlLayout` — the same geometry the window hit-tests with.
    var hovered: IslandControl? = nil

    /// The browser button under the cursor, if the cursor is on one.
    private var hoveredBrowserAction: BrowserAction? {
        guard case let .wingBrowser(action)? = hovered else { return nil }
        return action
    }

    /// The namespace the travelling hover highlight lives in.
    @Namespace private var hoverHighlight

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
        .padding(.leading, DesignTokens.wingInset + leadInset)
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
    ///
    /// The cluster is deliberately quiet until the cursor is in it. Then a
    /// single highlight TRAVELS to the segment under the pointer (one
    /// `matchedGeometryEffect`, so it slides between segments instead of two
    /// pills cross-fading), that segment's glyph lifts from secondary to full
    /// white and grows a little, and the cluster's hairline brightens. That is
    /// the same thing a macOS segmented control does, and it is what makes the
    /// buttons read as pressable rather than as decoration.
    private var browserControls: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: WingControlLayout.spacing) {
                ForEach(Array(WingControlLayout.controls.enumerated()), id: \.offset) { _, action in
                    browserButton(action)
                }
            }
            .background(Capsule().fill(DesignTokens.controlClusterFill))
            .overlay(
                Capsule().strokeBorder(
                    hoveredBrowserAction == nil
                        ? DesignTokens.controlClusterStroke
                        : DesignTokens.controlClusterStrokeActive,
                    lineWidth: 0.5
                )
            )
            // ONE animation for the whole cluster: the highlight's matched
            // geometry only interpolates when the insertion and the removal
            // happen in the same animated transaction, which a per-segment
            // animation cannot give it.
            .animation(DesignTokens.springHover, value: hoveredBrowserAction)
        }
        .padding(.trailing, DesignTokens.wingInset + trailingReserve)
    }

    private func browserButton(_ action: BrowserAction) -> some View {
        let isHovered = hoveredBrowserAction == action
        return Image(systemName: Self.symbol(for: action))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isHovered ? DesignTokens.textPrimary : DesignTokens.controlGlyphIdle)
            .scaleEffect(isHovered ? DesignTokens.hoverScale : 1)
            .frame(width: WingControlLayout.buttonSize, height: WingControlLayout.buttonSize)
            .background {
                // Exactly one segment carries the highlight at a time, so the
                // matched geometry has a single source and the pill SLIDES from
                // the segment being left to the one being entered.
                if isHovered {
                    Capsule()
                        .fill(DesignTokens.hoverHighlight)
                        .matchedGeometryEffect(id: "wing-browser-hover", in: hoverHighlight)
                }
            }
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
