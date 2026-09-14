import NotchHubCore
import SwiftUI

/// A high-fidelity, horizontally-extended bar visualizer.
///
/// Replaces the wave visualizer per user request for a more "real-time" feel.
/// It uses a series of rounded bars with varying heights driven by multiple
/// overlapping oscillators to simulate a reactive frequency spectrum.
struct MusicVisualizer: View {
    let isPlaying: Bool
    var color: Color = DesignTokens.accent
    
    /// Horizontally longer as requested (was 24).
    var width: CGFloat = 48
    var height: CGFloat = 14
    
    /// Number of bars in the visualizer.
    private let barCount = 12
    private let spacing: CGFloat = 2

    var body: some View {
        Group {
            if isPlaying {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    bars(phase: t)
                }
            } else {
                // When paused/stopped: show completely flat, dim idle bars (dots)
                // with zero movement and low opacity.
                flatBars
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func bars(phase: Double) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                let barWidth = (width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount)
                
                // We simulate "real-time" by combining three sine waves of different
                // frequencies for each bar. This creates a non-repeating, organic
                // "bouncing" effect that looks like a real EQ.
                let indexFactor = Double(i) / Double(barCount)
                let h1 = sin(phase * 4.0 + Double(i) * 0.8) * 0.5 + 0.5
                let h2 = sin(phase * 7.3 + Double(i) * 1.5) * 0.3 + 0.3
                let h3 = sin(phase * 2.1 - Double(i) * 0.4) * 0.2 + 0.2
                
                // Combine and scale. When not playing, we drop to a tiny "idle" height.
                let rawHeight = isPlaying ? (h1 + h2 + h3) : 0.15
                let barHeight = max(2.0, CGFloat(rawHeight) * height)

                // Each bar's colour is a point on the horizontal sweep, so the
                // strip transitions green → cyan left to right.
                let barColor = interpolate(t: indexFactor)

                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    // A vertical gradient per bar — brighter at the top, dimmer
                    // at the base — so the bars read as lit columns, not flat
                    // slabs. Combined with the horizontal sweep this gives the
                    // visualizer a real gradient instead of a single colour.
                    .fill(
                        LinearGradient(
                            colors: [barColor.opacity(0.95), barColor.opacity(0.40)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: barHeight)
                    // Add a slight opacity gradient across the bars for depth.
                    .opacity(0.6 + (1.0 - indexFactor) * 0.4)
            }
        }
    }

    /// Linearly interpolates between the sweep's two endpoints by `t` (0…1).
    ///
    /// The endpoints are authored as fixed RGB values so the sweep is cheap and
    /// deterministic — no need to round-trip through `NSColor` on every frame.
    private func interpolate(t: Double) -> Color {
        let r = 0.19 + (0.35 - 0.19) * t
        let g = 0.82 + (0.78 - 0.82) * t
        let b = 0.35 + (0.98 - 0.35) * t
        return Color(red: r, green: g, blue: b)
    }

    /// Flat, quiet resting dots when music is paused.
    private var flatBars: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                let barWidth = (width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.white.opacity(0.40)) // Increased opacity
                    .frame(width: barWidth, height: 3.0) // Increased height
            }
        }
    }
}

/// A sine wave shape that animates its phase and scales its amplitude.
struct WaveShape: Shape {
    var phase: Double
    var frequency: Double
    var strength: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let midY = height / 2
        
        // The wave is centered vertically and spans the full width.
        path.move(to: CGPoint(x: 0, y: midY))
        
        for x in stride(from: 0, to: width + 1, by: 1) {
            let relativeX = x / width
            // Sine wave formula: y = sin(x * freq + phase) * amplitude
            // We use a parabolic envelope so the wave tapers at the edges (0 at start/end).
            let envelope = 4 * relativeX * (1 - relativeX)
            let sine = sin(relativeX * .pi * 2 * frequency + phase)
            let y = midY + CGFloat(sine * envelope * strength) * (height / 2)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}
