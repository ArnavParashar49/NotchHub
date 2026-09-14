import NotchHubCore
import SwiftUI

/// The live-call control panel: the meeting's identity on top, a live timer,
/// and a row of circular controls for mute, camera, and leave.
///
/// The buttons are placed by `MeetingControlLayout`, which the window also
/// hit-tests against — the island never takes key focus, so clicks are routed
/// by position rather than by SwiftUI.
///
/// State is read from the `Meeting` — a muted mic turns warning, a live camera
/// turns on-air green — so the island always reflects what the call is doing.
struct MeetingView: View {
    let meeting: Meeting
    let onMute: () -> Void
    let onCamera: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MeetingControlLayout.rowSpacing) {
            header
            controls
        }
        .padding(.horizontal, MeetingControlLayout.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.space12) {
            Image(systemName: meeting.app.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: MeetingControlLayout.headerHeight, height: MeetingControlLayout.headerHeight)
                .background(
                    DesignTokens.chipFill,
                    in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous)
                )

            VStack(alignment: .leading, spacing: DesignTokens.space2) {
                Text(meeting.title)
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Text(meeting.context)
                    .font(DesignTokens.subtitleFont)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignTokens.space8) {
                Circle()
                    .fill(DesignTokens.onAir)
                    .frame(width: 6, height: 6)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(meeting.elapsedLabel(at: context.date))
                        .font(DesignTokens.numericFont)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .monospacedDigit()
                }
            }
        }
        .frame(height: MeetingControlLayout.headerHeight)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: MeetingControlLayout.buttonSpacing) {
            controlButton(
                symbol: meeting.isMuted ? "mic.slash.fill" : "mic.fill",
                tint: meeting.isMuted ? DesignTokens.warning : DesignTokens.accent,
                action: onMute
            )
            controlButton(
                symbol: meeting.isCameraOn ? "video.fill" : "video.slash.fill",
                tint: meeting.isCameraOn ? DesignTokens.onAir : DesignTokens.warning,
                action: onCamera
            )
            Spacer()
            controlButton(
                symbol: "phone.down.fill",
                tint: DesignTokens.live,
                action: onLeave
            )
        }
    }

    private func controlButton(symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: MeetingControlLayout.buttonSize, height: MeetingControlLayout.buttonSize)
                .background(DesignTokens.chipFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
