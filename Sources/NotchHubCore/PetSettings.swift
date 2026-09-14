import CoreGraphics
import Foundation

/// The pixel pet's few settings. Deliberately minimal: the pet is a companion,
/// not a virtual-pet game.
public struct PetSettings: Codable, Equatable, Sendable {
    public var showPet = true
    public var reactions = true
    public var idleAnimations = true
    public var interaction = true
    /// The pet gets up to mischief on its idle dock: hiding in the notch,
    /// peeking out, dashing to the other side, pouncing. Needs Idle Animations.
    public var mischief = true
    /// The fox's colours.
    public var look: PetLook = .fox
    /// What it wears on its head.
    public var hat: PetHatChoice = .seasonal
    /// It marks major holidays: a greeting, and a holiday hat when its hat is
    /// seasonal.
    public var holidays = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case showPet, reactions, idleAnimations, interaction, mischief, look, hat, holidays
    }

    /// Settings saved before a key existed keep every value they do have.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PetSettings()
        showPet = try container.decodeIfPresent(Bool.self, forKey: .showPet) ?? defaults.showPet
        reactions = try container.decodeIfPresent(Bool.self, forKey: .reactions) ?? defaults.reactions
        idleAnimations = try container.decodeIfPresent(Bool.self, forKey: .idleAnimations) ?? defaults.idleAnimations
        interaction = try container.decodeIfPresent(Bool.self, forKey: .interaction) ?? defaults.interaction
        mischief = try container.decodeIfPresent(Bool.self, forKey: .mischief) ?? defaults.mischief
        // An unknown look or hat (from a newer build) falls back to the default.
        look = (try? container.decodeIfPresent(PetLook.self, forKey: .look)) ?? defaults.look
        hat = (try? container.decodeIfPresent(PetHatChoice.self, forKey: .hat)) ?? defaults.hat
        holidays = try container.decodeIfPresent(Bool.self, forKey: .holidays) ?? defaults.holidays
    }

    private static let defaultsKey = "NotchHub.petSettings"

    public static func load() -> PetSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(PetSettings.self, from: data) else {
            return PetSettings()
        }
        return settings
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

/// Where the pet's panel hangs from: the island edge beside the pet when it was
/// clicked (screen x), on the pet's side of the notch.
public struct PetPanelAnchor: Equatable, Sendable {
    public var edge: CGFloat
    public var side: PetSide

    public init(edge: CGFloat, side: PetSide) {
        self.edge = edge
        self.side = side
    }
}

/// The small panel a click on the pet opens: a larger pet; a hello with the look
/// swatches and the hat button beside it; and a row of actions. Drawn by
/// `PetPanelView`, hit-tested by the window (`hit(at:in:notchInset:side:)`).
///
/// The content sits under the pet that was clicked: from the panel's right
/// edge when it hangs from a pet on the right, otherwise from its left edge.
public enum PetPanelLayout {
    public static let petScale: CGFloat = 3
    public static let horizontalInset: CGFloat = 18
    public static let spacing: CGFloat = 14
    public static let titleHeight: CGFloat = 18
    public static let rowGap: CGFloat = 6
    public static let chipSize = CGSize(width: 50, height: 24)
    public static let chipSpacing: CGFloat = 6
    public static let swatchSize: CGFloat = 12
    public static let swatchSpacing: CGFloat = 5
    public static let swatchToHatGap: CGFloat = 8
    public static let hatButtonSize = CGSize(width: 22, height: 18)

    /// The big pet's side.
    public static var petSize: CGFloat { PetLayout.artSize * petScale }

    /// The action chips side by side (and the title row above them).
    public static var chipsWidth: CGFloat {
        let count = CGFloat(PetInteraction.allCases.count)
        return chipSize.width * count + chipSpacing * (count - 1)
    }

    /// The pet, then the title row and chips.
    public static var contentWidth: CGFloat {
        petSize + spacing + chipsWidth
    }

    /// The narrowest panel that fits the content.
    public static var panelWidth: CGFloat {
        contentWidth + horizontalInset * 2
    }

    /// Where the content block starts, horizontally. Given the notch (same
    /// coordinates as `frame`), the big pet is kept out from under it, where its
    /// hat and its hops would be cut off (the panel is wide enough for that; see
    /// `NotchGeometry.petPanelFrame`).
    public static func contentMinX(in frame: CGRect, side: PetSide?, notch: CGRect? = nil) -> CGFloat {
        let minX = side == .right ? frame.maxX - horizontalInset - contentWidth : frame.minX + horizontalInset
        guard let notch, minX + petSize > notch.minX, minX < notch.maxX else { return minX }
        return notch.minX - petSize
    }

    /// Every hit target of the panel, in AppKit coordinates (origin bottom-left).
    public struct Layout {
        public var pet: CGRect
        public var actions: [(action: PetInteraction, rect: CGRect)]
        public var looks: [(look: PetLook, rect: CGRect)]
        public var hat: CGRect
    }

    /// The panel's targets for a frame; content sits below the notch strip.
    public static func layout(in frame: CGRect, notchInset: CGFloat, side: PetSide? = nil, notch: CGRect? = nil) -> Layout {
        let contentHeight = frame.height - notchInset
        let textBlock = titleHeight + rowGap + chipSize.height
        let blockHeight = max(textBlock, petSize)
        let top = frame.maxY - notchInset - ((contentHeight - blockHeight) / 2).rounded(.down)
        let minX = contentMinX(in: frame, side: side, notch: notch)
        let pet = CGRect(x: minX, y: top - (blockHeight + petSize) / 2, width: petSize, height: petSize)

        let textTop = top - (blockHeight - textBlock) / 2
        let x0 = minX + petSize + spacing
        let chipY = textTop - titleHeight - rowGap - chipSize.height
        let actions = PetInteraction.allCases.enumerated().map { index, action in
            (action, CGRect(x: x0 + CGFloat(index) * (chipSize.width + chipSpacing), y: chipY, width: chipSize.width, height: chipSize.height))
        }

        let titleMinY = textTop - titleHeight
        let hat = CGRect(x: x0 + chipsWidth - hatButtonSize.width, y: titleMinY + (titleHeight - hatButtonSize.height) / 2,
                         width: hatButtonSize.width, height: hatButtonSize.height)
        let count = CGFloat(PetLook.allCases.count)
        let swatchesMinX = hat.minX - swatchToHatGap - (swatchSize * count + swatchSpacing * (count - 1))
        let looks = PetLook.allCases.enumerated().map { index, look in
            (look, CGRect(x: swatchesMinX + CGFloat(index) * (swatchSize + swatchSpacing), y: titleMinY + (titleHeight - swatchSize) / 2,
                          width: swatchSize, height: swatchSize))
        }
        return Layout(pet: pet, actions: actions, looks: looks, hat: hat)
    }

    /// What a click in the panel lands on.
    public enum Hit: Equatable, Sendable {
        case action(PetInteraction)
        case look(PetLook)
        case hat
        case pet
    }

    public static func hit(at point: CGPoint, in frame: CGRect, notchInset: CGFloat, side: PetSide? = nil, notch: CGRect? = nil) -> Hit? {
        let layout = layout(in: frame, notchInset: notchInset, side: side, notch: notch)
        if let chip = layout.actions.first(where: { $0.rect.insetBy(dx: -2, dy: -3).contains(point) }) {
            return .action(chip.action)
        }
        if let swatch = layout.looks.first(where: { $0.rect.insetBy(dx: -2, dy: -3).contains(point) }) {
            return .look(swatch.look)
        }
        if layout.hat.insetBy(dx: -2, dy: -2).contains(point) {
            return .hat
        }
        if layout.pet.insetBy(dx: -3, dy: -3).contains(point) {
            return .pet
        }
        return nil
    }

    /// The action chips for a panel frame.
    public static func actions(in frame: CGRect, notchInset: CGFloat, side: PetSide? = nil) -> [(action: PetInteraction, rect: CGRect)] {
        layout(in: frame, notchInset: notchInset, side: side).actions
    }

    public static func action(at point: CGPoint, in frame: CGRect, notchInset: CGFloat, side: PetSide? = nil) -> PetInteraction? {
        guard case let .action(action)? = hit(at: point, in: frame, notchInset: notchInset, side: side) else { return nil }
        return action
    }
}
