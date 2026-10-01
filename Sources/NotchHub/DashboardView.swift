import NotchHubCore
import SwiftUI

/// The dashboard a click on the notch opens: a greeting, the time and date
/// with the weather, the next event (or what is playing), and a bar of status
/// and quick actions.
///
/// Every clickable area is placed by `DashboardLayout`, which the window
/// hit-tests — the island never takes key focus, so nothing here is a SwiftUI
/// `Button`. Keep the fixed row heights and chip widths in step with it.
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
    let timerElapsed: TimeInterval?
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
            battery
            if let focusMode {
                HStack(spacing: 4) {
                    Image(systemName: "moon.fill")
                    Text(focusMode)
                }
                .lineLimit(1)
            }
            if isCameraActive || isMicActive {
                Image(systemName: isCameraActive ? "video.fill" : "mic.fill")
                    .foregroundStyle(DesignTokens.live)
            }

            Spacer(minLength: 0)

            chip(width: DashboardLayout.timerChipWidth, active: timerElapsed != nil, enabled: timerEnabled) {
                Image(systemName: "timer")
                Text(timerElapsed.map { Activity.format($0) } ?? "Timer")
                    .monospacedDigit()
            }
            chip(width: DashboardLayout.glyphChipWidth, active: isTeleprompting, enabled: teleprompterEnabled) {
                Image(systemName: "text.alignleft")
            }
            chip(width: DashboardLayout.glyphChipWidth, active: isCameraPreviewing, enabled: cameraEnabled) {
                Image(systemName: "video.fill")
            }
            chip(width: DashboardLayout.trayChipWidth, active: false, enabled: true) {
                Image(systemName: "tray.full.fill")
                Text("\(trayCount)")
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(DesignTokens.textSecondary)
    }

    @ViewBuilder
    private var battery: some View {
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
                Text("\(batteryPercent)%")
                    .monospacedDigit()
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
