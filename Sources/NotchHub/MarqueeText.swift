import SwiftUI

/// A smooth, looping marquee / carousel text component.
///
/// When the text fits within `maxWidth`, it renders as standard static text.
/// When the text exceeds `maxWidth`, it smoothly scrolls horizontally back-and-forth
/// with a brief pause at each end, clipped within a bounded frame and
/// faded subtly at the trailing edge.
struct MarqueeText: View {
    let text: String
    let font: Font
    let foregroundStyle: Color
    let maxWidth: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        let isOverflowing = textWidth > maxWidth

        ZStack(alignment: .leading) {
            // Invisible background measurement of full unconstrained text width
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: TextWidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .hidden()

            // Visible text, translated if overflowing
            Text(text)
                .font(font)
                .foregroundStyle(foregroundStyle)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
        }
        .frame(width: min(maxWidth, max(20, textWidth)), alignment: .leading)
        .clipped()
        .mask(
            HStack(spacing: 0) {
                Rectangle().fill(Color.black)
                if isOverflowing {
                    LinearGradient(
                        colors: [Color.black, Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 8)
                }
            }
        )
        .onPreferenceChange(TextWidthPreferenceKey.self) { width in
            self.textWidth = width
            if width > maxWidth {
                startAnimation(overflowAmount: width - maxWidth)
            } else {
                stopAnimation()
            }
        }
        .onDisappear {
            stopAnimation()
        }
    }

    private func startAnimation(overflowAmount: CGFloat) {
        guard !isAnimating else { return }
        isAnimating = true
        
        let scrollDuration = Double(overflowAmount) / 20.0 + 1.0 // ~20 pt/sec speed
        
        func loop() {
            guard isAnimating else { return }
            
            // Pause at start
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard isAnimating else { return }
                
                withAnimation(.easeInOut(duration: scrollDuration)) {
                    offset = -overflowAmount - 4
                }
                
                // Pause at end
                DispatchQueue.main.asyncAfter(deadline: .now() + scrollDuration + 2.0) {
                    guard isAnimating else { return }
                    
                    withAnimation(.easeInOut(duration: scrollDuration)) {
                        offset = 0
                    }
                    
                    // Repeat
                    loop()
                }
            }
        }
        
        loop()
    }

    private func stopAnimation() {
        isAnimating = false
        offset = 0
    }
}

private struct TextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
