import NotchHubCore
import SwiftUI

// MARK: - Shared chrome

/// The notch strip every app panel carries: the clock on the left (a click
/// opens the dashboard) and "···" on the right (settings). Placed by
/// `AppPanelLayout`, which the window hit-tests.
struct AppPanelStrip: View {
    let notchInset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            TimelineView(.everyMinute) { context in
                Text(DashboardFormat.clock(context.date).time)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: AppPanelLayout.clockSize.width, height: AppPanelLayout.clockSize.height, alignment: .leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DesignTokens.textTertiary)
                .frame(width: AppPanelLayout.moreSize.width, height: AppPanelLayout.moreSize.height)
        }
        .padding(.horizontal, AppPanelLayout.horizontalInset)
        .frame(height: notchInset)
    }
}

/// An app's real icon, or a stand-in glyph.
struct AppIconView: View {
    let iconData: Data?
    let size: CGFloat

    var body: some View {
        if let iconData, let image = NSImage(data: iconData) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.7, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Browser

/// A browser's panel: the app and site, the tabs around the current one, and
/// navigation. Every clickable area matches `AppPanelLayout`.
struct BrowserPanelView: View {
    let notchInset: CGFloat
    let appName: String
    let iconData: Data?
    let browser: BrowserContext

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                header
                    .frame(height: AppPanelLayout.headerHeight)
                    .padding(.top, AppPanelLayout.topInset)
                tabCards(panelWidth: geo.size.width)
                    .frame(height: AppPanelLayout.tabCardHeight)
                    .padding(.top, AppPanelLayout.sectionGap)
                Spacer(minLength: 0)
                controls
                    .frame(height: AppPanelLayout.controlRowHeight)
                    .padding(.bottom, AppPanelLayout.bottomInset)
            }
            .padding(.horizontal, AppPanelLayout.horizontalInset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .overlay(alignment: .top) {
            AppPanelStrip(notchInset: notchInset).offset(y: -notchInset)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(iconData: iconData, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(browser.host ?? browser.title)
                    .font(DesignTokens.subtitleFont)
                    .foregroundStyle(DesignTokens.accent)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(browser.tabCount == 1 ? "1 tab" : "\(browser.tabCount) tabs")
                .font(DesignTokens.subtitleFont)
                .foregroundStyle(DesignTokens.textTertiary)
        }
    }

    private func tabCards(panelWidth: CGFloat) -> some View {
        let width = AppPanelLayout.tabCardWidth(panelWidth: panelWidth)
        return HStack(spacing: AppPanelLayout.tabCardSpacing) {
            ForEach(browser.nearbyTabs(limit: AppPanelLayout.maxTabCards), id: \.index) { tab in
                tabCard(tab, isActive: tab.index == browser.activeIndex)
                    .frame(width: width, height: AppPanelLayout.tabCardHeight)
            }
            Spacer(minLength: 0)
        }
    }

    private func tabCard(_ tab: BrowserTab, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tab.host ?? "")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(isActive ? DesignTokens.accent : DesignTokens.textTertiary)
                .lineLimit(1)
            Text(tab.title.isEmpty ? "Untitled" : tab.title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.14 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isActive ? DesignTokens.accent.opacity(0.6) : .clear, lineWidth: 1)
        )
    }

    private var controls: some View {
        HStack(spacing: AppPanelLayout.iconButtonSpacing) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("New Tab")
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignTokens.textPrimary)
            .frame(width: AppPanelLayout.newTabWidth, height: AppPanelLayout.controlRowHeight)
            .background(Capsule().fill(Color.white.opacity(0.08)))

            Spacer(minLength: 0)

            iconButton("chevron.left")
            iconButton("chevron.right")
            iconButton("arrow.clockwise")
        }
    }

    private func iconButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(DesignTokens.textPrimary)
            .frame(width: AppPanelLayout.iconButtonSize, height: AppPanelLayout.controlRowHeight)
            .background(Circle().fill(Color.white.opacity(0.08)))
    }
}

// MARK: - Coding agent

/// A coding agent's panel: model and state, the task, token / turn / time
/// stats, the context window, and plan limits where the tool records them.
struct AgentPanelView: View {
    let notchInset: CGFloat
    let iconData: Data?
    let session: AgentSession

    /// Extra height for plan-limit rows beyond the standard panel.
    static let limitRowHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: AppPanelLayout.headerHeight)
                .padding(.top, AppPanelLayout.topInset)

            Text(session.title ?? "No task title")
                .font(DesignTokens.subtitleFont)
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .topLeading)
                .padding(.top, AppPanelLayout.sectionGap)

            stats
                .padding(.top, AppPanelLayout.sectionGap)

            Spacer(minLength: 0)

            if let used = session.contextTokens, let fraction = session.contextFraction {
                meter(
                    label: "Context window",
                    value: "\(AgentFormat.tokens(used)) / \(AgentFormat.tokens(session.contextLimit)) · \(Int((fraction * 100).rounded()))%",
                    fraction: fraction
                )
            }
            ForEach(Array(session.limits.prefix(2).enumerated()), id: \.offset) { _, limit in
                meter(
                    label: limit.label,
                    value: [Self.resetText(limit.resetsAt), "\(Int(limit.usedPercent.rounded()))%"].compactMap { $0 }.joined(separator: "  "),
                    fraction: limit.usedPercent / 100
                )
            }
        }
        .padding(.horizontal, AppPanelLayout.horizontalInset)
        .padding(.bottom, AppPanelLayout.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            AppPanelStrip(notchInset: notchInset).offset(y: -notchInset)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(iconData: iconData, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.model ?? session.tool)
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text([session.tool, session.project].compactMap { $0 }.joined(separator: " · "))
                    .font(DesignTokens.subtitleFont)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle()
                    .fill(session.isWorking ? DesignTokens.warning : DesignTokens.textTertiary)
                    .frame(width: 6, height: 6)
                Text(session.isWorking ? "working" : "idle")
                    .font(DesignTokens.subtitleFont)
                    .foregroundStyle(session.isWorking ? DesignTokens.warning : DesignTokens.textTertiary)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(AgentFormat.tokens(session.tokens), caption: "tokens")
            stat("\(session.turns)", caption: "turns")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                stat(elapsed(now: context.date), caption: "elapsed")
            }
        }
        .frame(height: 36)
    }

    private func stat(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textPrimary)
            Text(caption)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func elapsed(now: Date) -> String {
        guard let start = session.startedAt else { return "—" }
        let end = session.isWorking ? now : (session.lastActivity ?? now)
        return Activity.format(max(0, end.timeIntervalSince(start)))
    }

    private func meter(label: String, value: String, fraction: Double) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .foregroundStyle(DesignTokens.textTertiary)
                Spacer(minLength: 8)
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(DesignTokens.warning)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
                }
            }
            .frame(height: 4)
        }
        .frame(height: 22)
        .padding(.top, 6)
    }

    /// "Resets Fri 3:30 PM".
    static func resetText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEjmm")
        return "Resets \(formatter.string(from: date))"
    }
}
