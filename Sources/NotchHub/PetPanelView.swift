import NotchHubCore
import SwiftUI

/// Neo's own little panel, opened by clicking the pet: a larger pet; a hello
/// with the look swatches and the hat button; and the actions. Placed by
/// `PetPanelLayout`, which the window hit-tests.
struct PetPanelView: View {
    let presentation: PetPresentation
    var look: PetLook = .fox
    var hat: PetHat? = nil
    var hatChoice: PetHatChoice = .seasonal
    var isFocusing = false
    /// "Hi, I'm Neo!", or today's holiday greeting.
    var greeting = PetIdentity.hello
    /// Focus can start (the Timers feature is on, or a session is running).
    var focusEnabled = true
    /// Where the content starts from the panel's left edge
    /// (`PetPanelLayout.contentMinX`); `nil` simply centres it.
    var contentLeading: CGFloat? = nil

    /// Centred, matching `PetPanelLayout` — which is what the window hit-tests
    /// against, so a chip can never draw in one place and be clicked in another.
    var body: some View {
        if let contentLeading {
            content
                .padding(.leading, contentLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var content: some View {
        HStack(spacing: PetPanelLayout.spacing) {
            PetView(presentation: presentation, scale: PetPanelLayout.petScale, look: look, hat: hat)
            VStack(alignment: .leading, spacing: PetPanelLayout.rowGap) {
                HStack(spacing: 0) {
                    Text(greeting)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    HStack(spacing: PetPanelLayout.swatchSpacing) {
                        ForEach(PetLook.allCases, id: \.self) { swatch($0) }
                    }
                    Color.clear.frame(width: PetPanelLayout.swatchToHatGap)
                    hatButton
                }
                .frame(width: PetPanelLayout.chipsWidth, height: PetPanelLayout.titleHeight)
                HStack(spacing: PetPanelLayout.chipSpacing) {
                    ForEach(PetInteraction.allCases, id: \.self) { action in
                        chip(action)
                    }
                }
            }
        }
    }

    private func chip(_ action: PetInteraction) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol(for: action))
                .font(.system(size: 9, weight: .semibold))
            Text(title(for: action))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(DesignTokens.textPrimary)
        .frame(width: PetPanelLayout.chipSize.width, height: PetPanelLayout.chipSize.height)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08)))
        .opacity(action == .focus && !focusEnabled ? 0.4 : 1)
    }

    private func swatch(_ option: PetLook) -> some View {
        Circle()
            .fill(PetCanvas.color(option.swatch))
            .frame(width: PetPanelLayout.swatchSize, height: PetPanelLayout.swatchSize)
            .overlay(
                Circle().strokeBorder(Color.white.opacity(option == look ? 0.95 : 0.18), lineWidth: option == look ? 1.5 : 0.5)
            )
            .accessibilityLabel(Text("\(option.title) look"))
    }

    private var hatButton: some View {
        Image(systemName: Self.symbol(for: hatChoice))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DesignTokens.textPrimary)
            .frame(width: PetPanelLayout.hatButtonSize.width, height: PetPanelLayout.hatButtonSize.height)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.08)))
            .accessibilityLabel(Text(hatChoice.title))
    }

    private func title(for action: PetInteraction) -> String {
        switch action {
        case .pet: return "Pet"
        case .feed: return "Feed"
        case .play: return "Play"
        case .trick: return "Tricks"
        case .focus: return isFocusing ? "Stop" : "Focus"
        case .sleep: return "Sleep"
        }
    }

    private func symbol(for action: PetInteraction) -> String {
        switch action {
        case .pet: return "hand.raised.fill"
        case .feed: return "fork.knife"
        case .play: return "tennisball.fill"
        case .trick: return "sparkles"
        case .focus: return isFocusing ? "stop.fill" : "timer"
        case .sleep: return "moon.zzz.fill"
        }
    }

    static func symbol(for choice: PetHatChoice) -> String {
        switch choice {
        case .seasonal: return "calendar"
        case .none: return "circle.slash"
        case .party: return "party.popper.fill"
        case .witch: return "moon.stars.fill"
        case .santa: return "snowflake"
        case .flowers: return "camera.macro"
        case .hearts: return "heart.fill"
        case .shamrock: return "leaf.fill"
        case .bunny: return "hare.fill"
        case .turkey: return "fork.knife"
        case .lunar: return "sparkles"
        case .marigold: return "sun.max.fill"
        }
    }
}
