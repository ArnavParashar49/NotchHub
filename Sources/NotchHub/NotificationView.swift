import NotchHubCore
import SwiftUI

/// A single notification surfaced into the island.
///
/// Plain value model — the app decides what to show; this view only renders it.
struct NotificationItem {
    let appName: String
    let appSymbol: String
    let sender: String
    let title: String
    let body: String
    let timestamp: Date
}

/// The island's notification surface.
///
/// Designed specifically for the notch, not as a Notification-Center clone:
/// a quiet app-identity strip, a sender line, and a message preview. In the
/// compact state only the app + a one-line preview are shown; expanded reveals
/// the full body with Dismiss / Open actions. Sharp corners throughout.
struct NotificationView: View {
    let item: NotificationItem
    let isExpanded: Bool
    let onDismiss: () -> Void
    let onOpen: () -> Void

    init(
        item: NotificationItem,
        isExpanded: Bool,
        onDismiss: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) {
        self.item = item
        self.isExpanded = isExpanded
        self.onDismiss = onDismiss
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.space8) {
            HStack(spacing: DesignTokens.space12) {
                appBadge
                VStack(alignment: .leading, spacing: DesignTokens.space2) {
                    Text(item.appName)
                        .font(DesignTokens.titleFont)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)
                    Text(item.sender)
                        .font(DesignTokens.subtitleFont)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isExpanded {
                    Text(preview)
                        .font(DesignTokens.subtitleFont)
                        .foregroundStyle(DesignTokens.textTertiary)
                        .lineLimit(1)
                }
            }

            if isExpanded {
                Text(item.body)
                    .font(DesignTokens.subtitleFont)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: DesignTokens.space8) {
                    actionButton("Open", symbol: "arrow.up.right", tint: DesignTokens.accent, action: onOpen)
                    actionButton("Dismiss", symbol: "xmark", tint: DesignTokens.textPrimary, action: onDismiss)
                }
            }
        }
        .padding(.horizontal, DesignTokens.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A one-line preview of the message for the compact state.
    private var preview: String {
        item.body.isEmpty ? item.title : item.body
    }

    // MARK: - App badge

    private var appBadge: some View {
        Image(systemName: item.appSymbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(DesignTokens.textPrimary)
            .frame(width: 34, height: 34)
            .background(DesignTokens.chipFill, in: Rectangle())
    }

    // MARK: - Actions

    private func actionButton(_ label: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.space4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(DesignTokens.compactFont)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, DesignTokens.space12)
            .frame(height: 28)
            .background(DesignTokens.chipFill, in: Rectangle())
        }
        .buttonStyle(.plain)
    }
}
