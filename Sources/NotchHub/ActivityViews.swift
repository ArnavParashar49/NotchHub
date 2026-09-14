import NotchHubCore
import SwiftUI

/// Per-activity expanded layouts.
///
/// The island is intentionally minimal: each kind gets a small bespoke
/// treatment (a progress track, a numeric readout, media controls) and
/// everything else falls back to the generic icon + title + subtitle layout
/// provided by `IslandView`.
enum ActivityViews {

    /// A full expanded layout for a given activity, or `nil` to use the
    /// generic layout. Kept as a single switch so new kinds are trivial to add.
    @ViewBuilder
    static func expandedLayout(for activity: Activity) -> some View {
        switch activity.kind {
        case .timer:
            TimerLayout(elapsed: activity.elapsed ?? 0)
        case .download:
            DownloadLayout(progress: activity.progress ?? 0)
        case .music:
            MusicLayout()
        default:
            EmptyView()
        }
    }
}

/// Timer: a large monospaced readout with a small progress ring.
struct TimerLayout: View {
    let elapsed: TimeInterval

    var body: some View {
        Text(Activity.format(elapsed))
            .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(DesignTokens.textPrimary)
    }
}

/// Download: a progress track with a percentage.
struct DownloadLayout: View {
    let progress: Double

    var body: some View {
        HStack(spacing: DesignTokens.space12) {
            ProgressView(value: progress)
                .tint(DesignTokens.accent)
                .frame(width: 110)
            Text("\(Int((progress * 100).rounded()))%")
                .font(DesignTokens.numericFont)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}

/// Music: play/pause and skip controls.
struct MusicLayout: View {
    var body: some View {
        HStack(spacing: DesignTokens.space12) {
            mediaButton("backward.fill")
            mediaButton("play.fill")
            mediaButton("forward.fill")
        }
    }

    private func mediaButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(DesignTokens.textPrimary)
            .frame(width: 34, height: 34)
            .background(DesignTokens.chipFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous))
    }
}
