import NotchHubCore
import SwiftUI

/// The dictation overlay: a compact strip showing that the Mac is listening
/// and what it has heard so far.
///
/// A live waveform rides the input level, the recognised text is the primary
/// line, and a red dot marks an active capture. Failed runs surface their
/// message in the warning color so nothing is silently dropped.
struct DictationView: View {
    let session: DictationSession
    let onStop: () -> Void

    /// A fixed pseudo-random seed so the bars hold a recognisable shape while
    /// their heights breathe with `level`.
    private static let bars: [CGFloat] = [
        0.35, 0.55, 0.80, 0.45, 0.65, 0.90, 0.50, 0.30, 0.70, 0.85,
        0.40, 0.60, 0.95, 0.55, 0.35, 0.75, 0.90, 0.45, 0.65, 0.50,
        0.80, 0.40, 0.60, 0.30,
    ]

    var body: some View {
        HStack(spacing: DesignTokens.space12) {
            micBadge
            waveform
            VStack(alignment: .leading, spacing: DesignTokens.space2) {
                Text(session.displayText)
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(session.elapsedLabel(at: context.date))
                        .font(DesignTokens.subtitleFont)
                        .foregroundStyle(DesignTokens.textTertiary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            stopButton
        }
        .padding(.horizontal, DesignTokens.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mic + live dot

    private var micBadge: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(micColor)
                .frame(width: 34, height: 34)
                .background(DesignTokens.chipFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous))
            if session.phase == .listening {
                Circle()
                    .fill(DesignTokens.live)
                    .frame(width: 7, height: 7)
                    .offset(x: 1, y: -1)
            }
        }
    }

    // MARK: - Waveform

    private var waveform: some View {
        HStack(alignment: .center, spacing: DesignTokens.space2) {
            ForEach(0..<Self.bars.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                    .fill(barColor)
                    .frame(width: 2.5, height: barHeight(index))
            }
        }
        .frame(height: 22)
        .animation(DesignTokens.springSettle, value: session.level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let seed = Self.bars[index]
        let base = 3 + seed * 8
        let lift = CGFloat(session.level) * 10 * seed
        return max(3, base + lift)
    }

    // MARK: - Stop

    private var stopButton: some View {
        Button(action: onStop) {
            Image(systemName: "stop.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: 30, height: 30)
                .background(DesignTokens.chipFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Colors

    private var micColor: Color {
        session.isActive ? DesignTokens.accent : DesignTokens.textTertiary
    }

    private var barColor: Color {
        session.isActive ? DesignTokens.accent : DesignTokens.textTertiary
    }

    private var textColor: Color {
        if case .failed = session.phase { return DesignTokens.warning }
        return DesignTokens.textPrimary
    }
}
