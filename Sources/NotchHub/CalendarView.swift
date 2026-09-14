import NotchHubCore
import SwiftUI

/// The next relevant calendar event.
///
/// Plain value model — the app decides when an event is worth surfacing and
/// passes the details here. `minutesUntil` drives the urgency copy.
struct CalendarEvent {
    let title: String
    let timeLabel: String
    let minutesUntil: Int
    let joinURL: String?
}

/// The island's next-event surface.
///
/// Compact: a quiet "Next" eyebrow with the event title and time. As the
/// event approaches the copy shifts to "Starts in 5 min". A `Join Meeting`
/// button appears when a join URL exists. Sharp corners, no borders.
struct CalendarView: View {
    let event: CalendarEvent
    let onJoin: () -> Void

    init(event: CalendarEvent, onJoin: @escaping () -> Void) {
        self.event = event
        self.onJoin = onJoin
    }

    var body: some View {
        HStack(spacing: DesignTokens.space12) {
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.accent)
                .frame(width: 34, height: 34)
                .background(DesignTokens.chipFill, in: Rectangle())

            VStack(alignment: .leading, spacing: DesignTokens.space2) {
                Text(event.title)
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DesignTokens.subtitleFont)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if event.joinURL != nil {
                joinButton
            }
        }
        .padding(.horizontal, DesignTokens.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Urgency-aware second line: approaching events read as a countdown.
    private var subtitle: String {
        if event.minutesUntil <= 15 {
            return "Starts in \(max(event.minutesUntil, 1)) min · \(event.timeLabel)"
        }
        return "Next · \(event.timeLabel)"
    }

    private var joinButton: some View {
        Button(action: onJoin) {
            HStack(spacing: DesignTokens.space4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Join Meeting")
                    .font(DesignTokens.compactFont)
            }
            .foregroundStyle(DesignTokens.islandFill)
            .padding(.horizontal, DesignTokens.space12)
            .frame(height: 28)
            .background(DesignTokens.accent, in: Rectangle())
        }
        .buttonStyle(.plain)
    }
}
