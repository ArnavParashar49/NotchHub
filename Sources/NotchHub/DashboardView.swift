import NotchHubCore
import SwiftUI

/// The dashboard a click on the notch opens: a greeting, the time and date
/// with the weather, the next event (or what is playing), and a bar of status
/// and quick actions.
///
/// Every clickable area is placed by `DashboardLayout`, which the window
/// hit-tests — the island never takes key focus, so nothing here is a SwiftUI
/// `Button`. Keep the fixed row heights in step with it; the quick actions
/// are drawn from its `quickActions` and `chipWidth`, so they cannot drift.
struct DashboardView: View {
    let notchInset: CGFloat
    let focus: DashboardFocus
    let nextEvent: UpcomingEvent?
    let nowPlayingTitle: String?
    let nowPlayingArtist: String?
    let weatherSymbol: String?
    let weatherLabel: String?
    let batteryPercent: Int?
    let isCharging: Bool
    let focusMode: String?
    let isMicActive: Bool
    let isCameraActive: Bool
    /// Settings → Lid Closed, for the lid chip: its look is
    /// `DashboardLidChip(lid)` (the app's own mapping), and its spoken value
    /// the features card's few words.
    let lid: LidSettingsModel
    /// Whether the stopwatch is running (its time is on the compact island,
    /// so the chip only lights up), and whether the feature is on.
    let isTimerRunning: Bool
    let timerEnabled: Bool
    /// Whether the teleprompter is showing, and whether the feature is on.
    let isTeleprompting: Bool
    let teleprompterEnabled: Bool
    /// Whether the camera preview is showing, and whether the feature is on.
    let isCameraPreviewing: Bool
    let cameraEnabled: Bool
    let trayCount: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { geo in
                layout(now: context.date, size: geo.size)
            }
        }
        .overlay(alignment: .topTrailing) { moreControl }
    }

    private func layout(now: Date, size: CGSize) -> some View {
        let columnStart = size.width * DashboardLayout.rightColumnFraction
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                clockColumn(now: now)
                    .padding(.leading, DashboardLayout.horizontalInset)
                    .frame(width: columnStart, alignment: .leading)
                focusColumn(now: now)
                    .padding(.trailing, DashboardLayout.horizontalInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, DashboardLayout.topInset)

            Spacer(minLength: 0)

            utilityBar
                .padding(.horizontal, DashboardLayout.horizontalInset)
                .frame(height: DashboardLayout.barHeight)
                .padding(.bottom, DashboardLayout.bottomInset)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: - Left: time

    private func clockColumn(now: Date) -> some View {
        let clock = DashboardFormat.clock(now)
        return VStack(alignment: .leading, spacing: 0) {
            Text(DashboardFormat.greeting(hour: Calendar.current.component(.hour, from: now)))
                .font(DesignTokens.subtitleFont)
                .foregroundStyle(DesignTokens.textTertiary)
                .frame(height: DashboardLayout.labelRowHeight, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(clock.time)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textPrimary)
                if let period = clock.period {
                    Text(period)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .lineLimit(1)
            .frame(height: 48, alignment: .leading)

            HStack(spacing: 4) {
                Text(DashboardFormat.dateLine(now))
                if let weatherSymbol, let weatherLabel {
                    Text("·")
                    Image(systemName: weatherSymbol)
                        .font(.system(size: 10, weight: .semibold))
                    Text(weatherLabel)
                }
            }
            .font(DesignTokens.subtitleFont)
            .foregroundStyle(DesignTokens.textSecondary)
            .lineLimit(1)
            .frame(height: DashboardLayout.detailRowHeight, alignment: .leading)
        }
    }

    // MARK: - Right: next event / now playing

    @ViewBuilder
    private func focusColumn(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch focus {
            case let .event(joinable):
                if let event = nextEvent {
                    columnLabel("up next")
                    titleRow(event.title, dot: DesignTokens.accent)
                    detailRow(DashboardFormat.eventTiming(event, now: now))
                    if joinable {
                        joinControl
                            .padding(.leading, DashboardLayout.detailIndent)
                            .padding(.top, DashboardLayout.joinGap)
                    }
                }
            case .nowPlaying:
                columnLabel("now playing")
                titleRow(nowPlayingTitle ?? "", dot: DesignTokens.onAir)
                detailRow(nowPlayingArtist ?? "")
            case .nothing:
                columnLabel("up next")
                Text("Nothing else today")
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(height: DashboardLayout.titleRowHeight, alignment: .leading)
            }
        }
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.subtitleFont)
            .foregroundStyle(DesignTokens.textTertiary)
            .frame(height: DashboardLayout.labelRowHeight, alignment: .leading)
    }

    private func titleRow(_ text: String, dot: Color) -> some View {
        HStack(spacing: DashboardLayout.detailIndent - 6) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(text)
                .font(DesignTokens.titleFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
        }
        .frame(height: DashboardLayout.titleRowHeight, alignment: .leading)
    }

    private func detailRow(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.subtitleFont)
            .foregroundStyle(DesignTokens.textSecondary)
            .lineLimit(1)
            .padding(.leading, DashboardLayout.detailIndent)
            .frame(height: DashboardLayout.detailRowHeight, alignment: .leading)
    }

    private var joinControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "video.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("Join")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(width: DashboardLayout.joinSize.width, height: DashboardLayout.joinSize.height)
        .background(
            Color(red: 0.20, green: 0.78, blue: 0.35),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    // MARK: - Bottom: status and quick actions

    private var utilityBar: some View {
        HStack(spacing: DashboardLayout.chipSpacing) {
            // Exactly what the chips leave (`minWidth: 0`: never more, so the
            // chips stay on the rects the window hit-tests at any width).
            status
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()

            ForEach(DashboardLayout.quickActions, id: \.self) { action in
                quickAction(action)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(DesignTokens.textSecondary)
    }

    /// The least of a focus mode's name worth showing ("Do…", "Work").
    static let focusNameMinimum: CGFloat = 28

    /// The battery, the focus mode and a live mic / camera. On a narrow
    /// panel they give way in turn — the focus name shortens, then the
    /// battery's percentage goes, then the battery (the menu bar has it too),
    /// then the focus, keeping the battery's bar if that still fits — so the
    /// live glyph is the last one standing. Without a focus mode: the
    /// percentage, then the battery.
    private var status: some View {
        ViewThatFits(in: .horizontal) {
            statusRow(showsFocus: true, showsPercent: true, showsBattery: true)
            statusRow(showsFocus: true, showsPercent: false, showsBattery: true)
            statusRow(showsFocus: true, showsPercent: false, showsBattery: false)
            statusRow(showsFocus: false, showsPercent: false, showsBattery: true)
            statusRow(showsFocus: false, showsPercent: false, showsBattery: false)
        }
    }

    private func statusRow(showsFocus: Bool, showsPercent: Bool, showsBattery: Bool) -> some View {
        HStack(spacing: DashboardLayout.chipSpacing) {
            if showsBattery {
                battery(showsPercent: showsPercent)
                    .layoutPriority(1)
            }
            if showsFocus, let focusMode {
                HStack(spacing: 4) {
                    Image(systemName: "moon.fill")
                    // Counted as a few letters when the bar measures what
                    // fits: the name takes what is left, shortened — and
                    // the focus gives way rather than show a bare "…".
                    Text(focusMode)
                        .frame(minWidth: 0, idealWidth: DashboardView.focusNameMinimum, alignment: .leading)
                }
                .lineLimit(1)
            }
            if isCameraActive || isMicActive {
                Image(systemName: isCameraActive ? "video.fill" : "mic.fill")
                    .foregroundStyle(DesignTokens.live)
            }
        }
    }

    /// One chip on the bar, `DashboardLayout.chipWidth(action)` wide, named
    /// for VoiceOver — most chips are a bare glyph.
    private func quickAction(_ action: DashboardAction) -> some View {
        quickActionChip(action)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(action))
            .accessibilityValue(accessibilityValue(action))
    }

    private func accessibilityLabel(_ action: DashboardAction) -> String {
        switch action {
        case .lidAwake: return "Keep working with the lid closed"
        case .timer: return "Timer"
        case .teleprompter: return "Teleprompter"
        case .camera: return "Camera"
        case .tray: return "Tray"
        case .settings, .join, .openPlayer: return ""
        }
    }

    private func accessibilityValue(_ action: DashboardAction) -> String {
        switch action {
        case .lidAwake: return lid.shortLabel
        case .timer: return isTimerRunning ? "Running" : "Stopped"
        case .teleprompter: return isTeleprompting ? "Showing" : ""
        case .camera: return isCameraPreviewing ? "Showing" : ""
        case .tray: return trayCount == 1 ? "1 item" : "\(trayCount) items"
        case .settings, .join, .openPlayer: return ""
        }
    }

    @ViewBuilder
    private func quickActionChip(_ action: DashboardAction) -> some View {
        let width = DashboardLayout.chipWidth(action)
        switch action {
        case .lidAwake:
            let lidChip = DashboardLidChip(lid)
            chip(width: width, active: lidChip == .awake, enabled: true) {
                Image(systemName: "laptopcomputer")
                    .overlay(alignment: .topTrailing) {
                        if lidChip == .waiting { waitingDot }
                    }
            }
        case .timer:
            chip(width: width, active: isTimerRunning, enabled: timerEnabled) {
                Image(systemName: "timer")
            }
        case .teleprompter:
            chip(width: width, active: isTeleprompting, enabled: teleprompterEnabled) {
                Image(systemName: "text.alignleft")
            }
        case .camera:
            chip(width: width, active: isCameraPreviewing, enabled: cameraEnabled) {
                Image(systemName: "video.fill")
            }
        case .tray:
            chip(width: width, active: false, enabled: true) {
                Image(systemName: "tray.full.fill")
                Text("\(trayCount)")
                    .monospacedDigit()
            }
        case .settings, .join, .openPlayer:
            EmptyView()
        }
    }

    /// The lid chip's dot ("on, waiting" — or sleep still off with the
    /// switch off): a small accent dot at the glyph's top-right, ringed in
    /// the island's black so it reads apart from it.
    private var waitingDot: some View {
        Circle()
            .fill(DesignTokens.accent)
            .frame(width: 5, height: 5)
            .padding(1.5)
            .background(Circle().fill(Color.black))
            .offset(x: 4, y: -4)
    }

    @ViewBuilder
    private func battery(showsPercent: Bool) -> some View {
        if let batteryPercent {
            let level = CGFloat(max(0, min(100, batteryPercent))) / 100
            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(batteryPercent <= 20 && !isCharging ? DesignTokens.warning : DesignTokens.textPrimary)
                        .frame(width: 22 * level)
                }
                .frame(width: 22, height: 4)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                if showsPercent {
                    Text("\(batteryPercent)%")
                        .monospacedDigit()
                }
            }
        }
    }

    private func chip<Label: View>(
        width: CGFloat,
        active: Bool,
        enabled: Bool,
        @ViewBuilder label: () -> Label
    ) -> some View {
        HStack(spacing: 4) { label() }
            .foregroundStyle(active ? DesignTokens.accent : DesignTokens.textPrimary)
            .frame(width: width, height: DashboardLayout.barHeight)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
    }

    /// "···" in the notch strip, beside the cutout: opens settings.
    private var moreControl: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(DesignTokens.textTertiary)
            .frame(width: DashboardLayout.moreSize.width, height: DashboardLayout.moreSize.height)
            .padding(.trailing, DashboardLayout.horizontalInset)
            .offset(y: -(notchInset / 2 + DashboardLayout.moreSize.height / 2))
    }
}
