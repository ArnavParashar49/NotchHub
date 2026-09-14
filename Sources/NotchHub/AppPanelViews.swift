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

/// A browser's panel: the page you are on with a back / forward / reload
/// capsule, then the tabs around the current one as rows, under a "Tabs"
/// label with New Tab beside it. Every clickable area matches
/// `AppPanelLayout`.
struct BrowserPanelView: View {
    let notchInset: CGFloat
    let appName: String
    let iconData: Data?
    let browser: BrowserContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: AppPanelLayout.browserHeaderHeight)
                .padding(.top, AppPanelLayout.browserTopInset)
            tabsHeader
                .frame(height: AppPanelLayout.tabsHeaderHeight)
                .padding(.top, AppPanelLayout.tabsHeaderGap)
            VStack(spacing: AppPanelLayout.tabRowSpacing) {
                ForEach(browser.nearbyTabs(limit: AppPanelLayout.maxTabRows), id: \.index) { tab in
                    tabRow(tab, isActive: tab.index == browser.activeIndex)
                }
            }
            .padding(.top, AppPanelLayout.tabRowsGap)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppPanelLayout.horizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            AppPanelStrip(notchInset: notchInset).offset(y: -notchInset)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(iconData: iconData, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(browser.title.isEmpty ? appName : browser.title)
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(browser.host ?? appName)
                    .font(DesignTokens.subtitleFont)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 12)
            navigation
        }
    }

    /// Back, forward and reload as segments of one capsule.
    private var navigation: some View {
        HStack(spacing: 0) {
            ForEach(Array(AppPanelLayout.navControls.enumerated()), id: \.offset) { index, action in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 0.5, height: 12)
                        .frame(width: 0)
                }
                Image(systemName: WingView.symbol(for: action))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(width: AppPanelLayout.navButtonSize.width, height: AppPanelLayout.navButtonSize.height)
            }
        }
        .background(Capsule().fill(DesignTokens.controlClusterFill))
        .overlay(Capsule().strokeBorder(DesignTokens.controlClusterStroke, lineWidth: 0.5))
    }

    // MARK: Tabs

    private var tabsHeader: some View {
        HStack(spacing: 6) {
            Text("TABS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(DesignTokens.textTertiary)
            Text("\(browser.tabCount)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .heavy))
                Text("New Tab")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(DesignTokens.accent)
            .frame(width: AppPanelLayout.newTabSize.width, height: AppPanelLayout.newTabSize.height)
            .background(Capsule().fill(DesignTokens.accent.opacity(0.14)))
        }
    }

    private func tabRow(_ tab: BrowserTab, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            TabMonogram(tab: tab)
            Text(tab.title.isEmpty ? "Untitled" : tab.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isActive ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let host = tab.host {
                Text(host)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            if isActive {
                Circle()
                    .fill(DesignTokens.accent)
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: AppPanelLayout.tabRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.10 : 0.035))
        )
    }
}

/// A tab's stand-in favicon: the site's initial on a colour picked from its
/// host, so the same site always gets the same tile.
private struct TabMonogram: View {
    let tab: BrowserTab

    var body: some View {
        let seed = tab.host ?? tab.title
        Text(seed.first.map { String($0).uppercased() } ?? "·")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(width: 18, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(hue: Self.hue(for: seed), saturation: 0.42, brightness: 0.58))
            )
    }

    /// A stable hue (Swift's `hashValue` changes every launch).
    static func hue(for text: String) -> Double {
        var hash: UInt32 = 5381
        for scalar in text.unicodeScalars {
            hash = (hash &* 33) &+ scalar.value
        }
        return Double(hash % 360) / 360
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
