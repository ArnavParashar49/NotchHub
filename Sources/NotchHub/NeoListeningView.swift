import NotchHubCore
import SwiftUI

/// NEO's listening mark: a tiny voice meter beside the pet while NEO's
/// microphone is live, with the word "Listening" for the first moment.
///
/// Four thin rounded bars in the island's calm green, 14 pt wide and at most
/// 12 pt tall. They move to their own slow rhythm
/// (`NeoListeningLayout.level`) — NEO's core says THAT it is listening, not
/// how loud the room is, so the bars claim no level. With Reduce Motion they
/// stand still. The word sits on the notch's side of the bars, so the bars
/// never move relative to the pet when it leaves.
///
/// The view stays in the island beside the pet whether or not NEO is
/// listening — drawing nothing, with its clock paused, while it is not — and
/// the mark, and its word, come and go by opacity and scale. A view that is
/// already there travels with the island's edge when the island springs, as
/// the pet does; one inserted at that moment would appear at its final place
/// while the pet was still on its way there.
///
/// Drawn only: it takes no clicks and no hover (`IslandView` turns hit
/// testing off for its layer, and the window never routes a click to it).
struct NeoListeningView: View {
    /// The mark to show, or `nil` while NEO is not listening.
    let mark: NeoListeningMark?
    /// On the left of the notch the row is mirrored: the pet, the bars, then
    /// the word — still toward the notch.
    var mirrored = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the last stretch of listening began, so the bars keep their
    /// rhythm (rather than jumping) while the mark fades out.
    @State private var lastSince: Date?

    private var shown: Bool { mark != nil }
    private var showsLabel: Bool { mark?.showsLabel ?? false }

    var body: some View {
        HStack(spacing: NeoListeningLayout.gap) {
            if !mirrored { label }
            bars
            if mirrored { label }
        }
        .frame(height: NeoListeningLayout.markHeight)
        // Appearing and leaving on whatever spring is moving the island: the
        // mark grows out of, and shrinks back toward, the pet.
        .scaleEffect(shown ? 1 : 0.5, anchor: mirrored ? .leading : .trailing)
        .opacity(shown ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NeoListeningIndicator.accessibilityLabel)
        .accessibilityHidden(!shown)
        .onChange(of: mark?.since) { since in
            if let since { lastSince = since }
        }
    }

    /// The word: it arrives once the island has started to make room and
    /// leaves quickly, before the island has closed over it — the island's
    /// own rule for content. Its place in the row is a fixed-width slot that
    /// travels on the island's spring; only the fade inside it keeps its own
    /// timing.
    private var label: some View {
        Color.clear
            .frame(width: min(IslandMetrics.listeningLabelWidth, NeoListeningLayout.maxLabelWidth), height: NeoListeningLayout.markHeight)
            .overlay(alignment: mirrored ? .leading : .trailing) {
                Text(NeoListeningIndicator.label)
                    .font(DesignTokens.compactFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(showsLabel ? 1 : 0)
                    .animation(showsLabel ? DesignTokens.contentIn : DesignTokens.contentOut, value: showsLabel)
            }
    }

    @ViewBuilder
    private var bars: some View {
        Group {
            if reduceMotion {
                row(NeoListeningLayout.restingLevels)
            } else {
                // Paused while NEO is not listening: nothing is drawn, and
                // nothing ticks.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shown)) { context in
                    let since = mark?.since ?? lastSince ?? context.date
                    let time = context.date.timeIntervalSince(since)
                    row((0..<NeoListeningLayout.barCount).map { NeoListeningLayout.level(bar: $0, at: time) })
                }
            }
        }
        .frame(width: NeoListeningLayout.markWidth, height: NeoListeningLayout.markHeight)
    }

    /// The bars, centred on the row's midline so they open both ways like a
    /// voice meter.
    private func row(_ levels: [Double]) -> some View {
        HStack(alignment: .center, spacing: NeoListeningLayout.barSpacing) {
            ForEach(0..<NeoListeningLayout.barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(DesignTokens.listening)
                    .frame(
                        width: NeoListeningLayout.barWidth,
                        height: NeoListeningLayout.barHeight(level: index < levels.count ? levels[index] : NeoListeningLayout.minLevel)
                    )
            }
        }
    }
}
