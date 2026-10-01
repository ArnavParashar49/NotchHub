import NotchHubCore
import SwiftUI

/// The teleprompter, reading.
///
/// The script is one block of text offset upward by a distance derived from the
/// clock, inside a `TimelineView(.animation)` so the offset is recomputed once
/// per display frame. That is the whole trick: SwiftUI never animates anything
/// here, so there is no spring to fight, no interpolation to drift and nothing
/// to stutter — every frame simply asks the state where the text should be at
/// this instant, and `TeleprompterState` answers from the elapsed time.
///
/// The reading window fades at both edges and carries a soft focus band across
/// its middle, so the eye has a fixed line to sit on while the words come up to
/// meet it — the thing that makes a teleprompter readable rather than just
/// scrolling text.
struct TeleprompterView: View {
    let state: TeleprompterState
    let notchInset: CGFloat
    /// The panel's own size, so the reading window can be measured exactly the
    /// way `TeleprompterLayout` measures it for hit testing.
    let size: CGSize
    /// Reports the measured scroll distance back, so the state knows where the
    /// script ends.
    let onMeasure: (Double) -> Void

    /// The reading face. Large, generously leaded, and rounded like the rest of
    /// the island — a teleprompter is read at a glance from a distance.
    private static let font = Font.system(size: 19, weight: .semibold, design: .rounded)
    private static let lineSpacing: CGFloat = 7
    /// One rendered line, near enough: the point size at SF's default leading,
    /// plus the extra line spacing. The focus band is sized from it.
    private static let lineHeight: CGFloat = 19 * 1.25 + lineSpacing
    /// Where the first line comes to rest, as a fraction of the window height —
    /// high enough to leave a run-up, low enough to keep lines in view after.
    private static let focusFraction: CGFloat = 1.0 / 3.0

    var body: some View {
        VStack(spacing: 0) {
            reader
            controlBar
                .frame(height: TeleprompterLayout.barHeight)
                .padding(.bottom, TeleprompterLayout.barBottomInset)
        }
        .padding(.horizontal, TeleprompterLayout.horizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The window the script moves through.
    private var readingHeight: CGFloat {
        let frame = CGRect(origin: .zero, size: size)
        return TeleprompterLayout.readingFrame(in: frame, notchInset: notchInset).height
    }

    private var reader: some View {
        TimelineView(.animation) { context in
            let offset = state.offset(at: context.date)
            ZStack(alignment: .top) {
                Text(state.script)
                    .font(Self.font)
                    .lineSpacing(Self.lineSpacing)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Starts at the focus line, so the first line arrives ON
                    // the band rather than at the very top edge.
                    .padding(.top, readingHeight * Self.focusFraction)
                    .offset(y: -offset)
                    .background(measuringOverlay)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: readingHeight, alignment: .top)
            .clipped()
            .overlay(focusBand)
            .mask(edgeFade)
            .padding(.top, TeleprompterLayout.readingTopInset)
            .padding(.bottom, TeleprompterLayout.readingBottomGap)
        }
    }

    /// Measures the rendered script and reports how far it can scroll: its own
    /// height, plus the lead-in, less the window, plus a tail so the last line
    /// comes to rest ON the focus band instead of at the window's top edge.
    private var measuringOverlay: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ScriptHeightKey.self, value: proxy.size.height)
        }
        .onPreferenceChange(ScriptHeightKey.self) { height in
            guard height > 0 else { return }
            // The text's own height plus the lead-in, less the window: the
            // distance that brings the LAST line to the focus band.
            let distance = height - readingHeight * (1 - Self.focusFraction)
            onMeasure(max(0, Double(distance)))
        }
    }

    /// The line the eye sits on. A whisper — any more and it competes with the
    /// words it is there to serve.
    private var focusBand: some View {
        // An overlay is centred, so the offset is measured from the middle of
        // the window to the middle of the first line's resting place.
        let centre = readingHeight * Self.focusFraction + Self.lineHeight / 2
        return Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: Self.lineHeight + 6)
            .offset(y: centre - readingHeight / 2)
            .allowsHitTesting(false)
    }

    /// Lines arrive and leave through a fade rather than being cut off by a
    /// hard edge, which is what stops the clip reading as a crop.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.80),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Controls

    /// Drawn, not buttons — the prompter must never take focus from the app the
    /// user is presenting from. `TeleprompterLayout` owns the geometry, and the
    /// window hit-tests against exactly these numbers.
    private var controlBar: some View {
        HStack(spacing: TeleprompterLayout.buttonSpacing) {
            button(state.isRunning ? "pause.fill" : "play.fill", prominent: true)
            button("arrow.counterclockwise")
            Spacer(minLength: 0)
            button("minus", enabled: state.canGoSlower)
            Text(state.speedLabel)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: TeleprompterLayout.speedWidth, height: TeleprompterLayout.buttonSize.height)
            button("plus", enabled: state.canGoFaster)
            Spacer(minLength: 0)
            button("pencil")
            button("xmark")
        }
        .overlay(alignment: .bottom) { progressHairline }
    }

    private func button(_ symbol: String, prominent: Bool = false, enabled: Bool = true) -> some View {
        Image(systemName: symbol)
            .font(.system(size: prominent ? 11 : 10, weight: .bold))
            .foregroundStyle(prominent ? DesignTokens.controlPrimaryGlyph : DesignTokens.textPrimary)
            .frame(width: TeleprompterLayout.buttonSize.width, height: TeleprompterLayout.buttonSize.height)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(prominent ? DesignTokens.controlPrimaryFill : DesignTokens.chipFill)
            )
            .opacity(enabled ? 1 : 0.32)
    }

    /// How far through the script the reader is — a hairline along the foot of
    /// the panel, so progress is visible without a number to read.
    ///
    /// It carries its own faint track. Without one, a short run looked like an
    /// underline under whichever buttons it happened to reach rather than a
    /// measure of the whole script.
    private var progressHairline: some View {
        TimelineView(.periodic(from: .now, by: 1 / 12)) { context in
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(DesignTokens.textPrimary.opacity(0.30))
                        .frame(width: max(0, proxy.size.width * state.progress(at: context.date)))
                }
            }
        }
        .frame(height: 2)
        .offset(y: 8)
    }
}

/// Carries the rendered script's height out of the layout pass.
private struct ScriptHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Compose

/// The teleprompter, being written.
///
/// A real `TextEditor`, so this is the one teleprompter mode that takes key
/// focus — you cannot type into a drawn control. Reading mode gives the focus
/// straight back.
struct TeleprompterComposeView: View {
    @Binding var script: String
    let onStart: () -> Void
    let onOpenFile: () -> Void
    let onPaste: () -> Void
    let onClose: () -> Void

    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            editor
            footer
        }
        .padding(.horizontal, TeleprompterLayout.horizontalInset)
        .padding(.top, 10)
        .padding(.bottom, TeleprompterLayout.barBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { editorFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary)
            Text("Teleprompter")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer(minLength: 0)
            Text(wordCountLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textTertiary)
        }
    }

    private var wordCountLabel: String {
        let words = script.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return "Paste or type a script" }
        // At the default reading pace, so the number is an actual estimate.
        let seconds = Double(words) / 130 * 60
        return "\(words) words · about \(max(1, Int(seconds / 60))) min"
    }

    private var editor: some View {
        TextEditor(text: $script)
            .focused($editorFocused)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(DesignTokens.textPrimary)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignTokens.fieldFill)
            )
            .overlay(alignment: .topLeading) {
                if script.isEmpty {
                    Text("Paste your script here, or open a text file.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textTertiary)
                        .padding(.horizontal, 13)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            chip("Open…", symbol: "folder", action: onOpenFile)
            chip("Paste", symbol: "doc.on.clipboard", action: onPaste)
            Spacer(minLength: 0)
            chip("Close", symbol: "xmark", action: onClose)
            Button(action: onStart) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Start")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(Capsule().fill(Color.white))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(DesignTokens.chipFill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
