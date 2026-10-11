import CoreGraphics
import Foundation

/// The pixel pet's settings: whether it shows and what it does, and how it is
/// made one's own — its colours, what it wears, its size and side of the
/// notch, its temperament and its name. Deliberately not a virtual-pet game:
/// nothing here needs looking after.
///
/// Every value has a default that is the pet as it always was, so settings
/// saved by an older build decode unchanged, and a value a newer build saved
/// that this one does not know falls back to its default.
public struct PetSettings: Codable, Equatable, Sendable {
    public var showPet = true
    public var reactions = true
    public var idleAnimations = true
    public var interaction = true
    /// The pet gets up to mischief on its idle dock: hiding in the notch,
    /// peeking out, dashing to the other side, pouncing. Needs Idle Animations.
    public var mischief = true
    /// The fox's colours: a preset look…
    public var look: PetLook = .fox
    /// …or, when on, a fur colour of the user's own (`customFur`).
    public var usesCustomFur = false
    /// The picked fur colour. What is drawn is derived from it within
    /// legibility bounds (`PetPalette.custom`).
    public var customFur = PetFurColor.default
    /// The tint of NEO's wake outline; the stored `glow` key stays for compatibility.
    public var glow: PetGlowColor = .teal
    /// What it wears on its head.
    public var hat: PetHatChoice = .seasonal
    /// What else it wears: one accessory, with any hat.
    public var accessory: PetAccessoryChoice = .none
    /// It marks major holidays: a greeting, and a holiday hat when its hat is
    /// seasonal.
    public var holidays = true
    /// How big it is in the notch strip.
    public var size: PetSize = .normal
    /// Which side of the notch it lives on.
    public var home: PetHome = .right
    /// How lively it is: how often it fidgets and plays, how soon it dozes.
    public var energy: PetEnergy = .normal
    /// It sleeps through the night (`nightStart` to `nightEnd`), unless NEO
    /// is doing something or the user is with it.
    public var sleepsAtNight = false
    /// The hour (0–23) its night begins.
    public var nightStart = 22
    /// The hour (0–23) its night ends. A night may run past midnight.
    public var nightEnd = 7
    /// What it is called, as typed. Shown as `displayName`.
    public var name = PetIdentity.name

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case showPet, reactions, idleAnimations, interaction, mischief, look, hat, holidays
        case usesCustomFur, customFur, glow, accessory, size, home, energy
        case sleepsAtNight, nightStart, nightEnd, name
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
        // The customisation keys: missing, of another type, or a value this
        // build does not know — each falls back on its own.
        usesCustomFur = (try? container.decodeIfPresent(Bool.self, forKey: .usesCustomFur)) ?? defaults.usesCustomFur
        customFur = (try? container.decodeIfPresent(PetFurColor.self, forKey: .customFur)) ?? defaults.customFur
        glow = (try? container.decodeIfPresent(PetGlowColor.self, forKey: .glow)) ?? defaults.glow
        accessory = (try? container.decodeIfPresent(PetAccessoryChoice.self, forKey: .accessory)) ?? defaults.accessory
        size = (try? container.decodeIfPresent(PetSize.self, forKey: .size)) ?? defaults.size
        home = (try? container.decodeIfPresent(PetHome.self, forKey: .home)) ?? defaults.home
        energy = (try? container.decodeIfPresent(PetEnergy.self, forKey: .energy)) ?? defaults.energy
        sleepsAtNight = (try? container.decodeIfPresent(Bool.self, forKey: .sleepsAtNight)) ?? defaults.sleepsAtNight
        nightStart = PetNight.hour((try? container.decodeIfPresent(Int.self, forKey: .nightStart)) ?? defaults.nightStart)
        nightEnd = PetNight.hour((try? container.decodeIfPresent(Int.self, forKey: .nightEnd)) ?? defaults.nightEnd)
        name = PetIdentity.validName((try? container.decodeIfPresent(String.self, forKey: .name)) ?? defaults.name)
    }

    /// The name to show: `name` trimmed, at most 16 characters, "Neo" if empty.
    public var displayName: String { PetIdentity.validName(name) }

    /// The colours the fox is drawn in. Derive it when the settings change and
    /// keep it — not per frame.
    public var palette: PetPalette {
        usesCustomFur ? .custom(customFur) : .look(look)
    }

    /// The wake outline's colour; `nil` is the design token's teal.
    public var glowColor: UInt32? { glow.rgb(palette: palette) }

    /// Its night, when it sleeps through one.
    public var night: PetNight? {
        sleepsAtNight ? PetNight(startHour: nightStart, endHour: nightEnd) : nil
    }

    /// These settings as they are stored: the name valid, the hours in range.
    public var normalized: PetSettings {
        var copy = self
        copy.name = displayName
        copy.nightStart = PetNight.hour(nightStart)
        copy.nightEnd = PetNight.hour(nightEnd)
        return copy
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
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

/// The small panel a click on the pet opens: a larger pet; a hello with the look
/// swatches and the hat button beside it; and a row of actions. Drawn by
/// `PetPanelView`, hit-tested by the window (`hit(at:in:notchInset:)`).
///
/// The content is CENTRED in the panel, which is itself centred on the notch —
/// so the panel opens as a symmetric stretch out of the compact bar rather than
/// lurching toward whichever side the pet happened to be clicked on.
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
    /// The "more…" dot left of the swatches (it opens Settings → the pet's
    /// page): a swatch's size, a swatch's spacing away.
    public static var moreSize: CGFloat { swatchSize }

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

    /// Where the content block starts, horizontally: centred in the panel.
    ///
    /// The panel is centred on the notch and is wider than `contentWidth`, so a
    /// centred block leaves equal margins and puts the big pet clear to the left
    /// of the cutout, where its hat and its hops are never cut off.
    public static func contentMinX(in frame: CGRect) -> CGFloat {
        (frame.midX - contentWidth / 2).rounded()
    }

    /// Every hit target of the panel, in AppKit coordinates (origin bottom-left).
    public struct Layout {
        public var pet: CGRect
        public var actions: [(action: PetInteraction, rect: CGRect)]
        public var looks: [(look: PetLook, rect: CGRect)]
        public var hat: CGRect
        /// "More…": opens the pet's page in Settings.
        public var more: CGRect
    }

    /// The panel's targets for a frame; content sits below the notch strip.
    public static func layout(in frame: CGRect, notchInset: CGFloat) -> Layout {
        let contentHeight = frame.height - notchInset
        let textBlock = titleHeight + rowGap + chipSize.height
        let blockHeight = max(textBlock, petSize)
        let top = frame.maxY - notchInset - ((contentHeight - blockHeight) / 2).rounded(.down)
        let minX = contentMinX(in: frame)
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
        let more = CGRect(x: swatchesMinX - swatchSpacing - moreSize, y: titleMinY + (titleHeight - moreSize) / 2,
                          width: moreSize, height: moreSize)
        return Layout(pet: pet, actions: actions, looks: looks, hat: hat, more: more)
    }

    /// The room the title row leaves the greeting, left of "more…".
    public static var greetingWidth: CGFloat {
        let count = CGFloat(PetLook.allCases.count)
        let controls = hatButtonSize.width + swatchToHatGap + swatchSize * count + swatchSpacing * (count - 1) + swatchSpacing + moreSize
        return chipsWidth - controls - 6
    }

    /// What a click in the panel lands on.
    public enum Hit: Equatable, Sendable {
        case action(PetInteraction)
        case look(PetLook)
        case hat
        case pet
        /// "More…": the pet's page in Settings.
        case more
    }

    public static func hit(at point: CGPoint, in frame: CGRect, notchInset: CGFloat) -> Hit? {
        let layout = layout(in: frame, notchInset: notchInset)
        if let chip = layout.actions.first(where: { $0.rect.insetBy(dx: -2, dy: -3).contains(point) }) {
            return .action(chip.action)
        }
        if let swatch = layout.looks.first(where: { $0.rect.insetBy(dx: -2, dy: -3).contains(point) }) {
            return .look(swatch.look)
        }
        if layout.hat.insetBy(dx: -2, dy: -2).contains(point) {
            return .hat
        }
        if layout.more.insetBy(dx: -2, dy: -3).contains(point) {
            return .more
        }
        if layout.pet.insetBy(dx: -3, dy: -3).contains(point) {
            return .pet
        }
        return nil
    }

    /// The action chips for a panel frame.
    public static func actions(in frame: CGRect, notchInset: CGFloat) -> [(action: PetInteraction, rect: CGRect)] {
        layout(in: frame, notchInset: notchInset).actions
    }

    public static func action(at point: CGPoint, in frame: CGRect, notchInset: CGFloat) -> PetInteraction? {
        guard case let .action(action)? = hit(at: point, in: frame, notchInset: notchInset) else { return nil }
        return action
    }
}
