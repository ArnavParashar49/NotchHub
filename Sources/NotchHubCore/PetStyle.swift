import Foundation

/// Who the pet is: the fox in the notch is NEO, the voice assistant — its
/// poses are what NEO is doing (`PetBrain.neoAnimation`).
public enum PetIdentity {
    /// The fox's name.
    public static let name = "Neo"
    /// What it says when its panel opens (a holiday greeting takes its place).
    public static var hello: String { "Hi, I'm \(name)!" }
}

/// The fox's colours: a palette swap of its fur (`art/pet/looks.txt`), so every
/// frame in the art set works in every look without being redrawn. Props and
/// effects keep their own colours, and so do hats.
public enum PetLook: String, CaseIterable, Codable, Sendable {
    /// The art's own orange fox.
    case fox
    case arctic
    case silver
    case sand

    public var title: String {
        switch self {
        case .fox: return "Fox"
        case .arctic: return "Arctic"
        case .silver: return "Silver"
        case .sand: return "Sand"
        }
    }

    /// The colour a pixel of `rgb` is drawn in with this look.
    public func color(_ rgb: UInt32) -> UInt32 {
        Self.maps[self]?[rgb] ?? rgb
    }

    /// The look's fur colour, for a swatch.
    public var swatch: UInt32 {
        let fur = PetArt.palette["o"] ?? 0xE97A2E
        return color(fur)
    }

    /// Base colour → this look's colour, built once from the generated art.
    private static let maps: [PetLook: [UInt32: UInt32]] = {
        var maps: [PetLook: [UInt32: UInt32]] = [:]
        for look in PetLook.allCases where look != .fox {
            guard let overrides = PetArt.looks[look.rawValue] else { continue }
            var map: [UInt32: UInt32] = [:]
            for (key, rgb) in overrides {
                if let base = PetArt.palette[key] { map[base] = rgb }
            }
            maps[look] = map
        }
        return maps
    }()
}

/// Hats the fox can wear (`art/pet/hats.pet`), drawn on each frame's head
/// anchor (`art/pet/anchors`).
public enum PetHat: String, CaseIterable, Codable, Sendable {
    case party, witch, santa, flowers
    // Holiday hats (art/pet/holiday_hats.pet)
    case hearts, shamrock, bunny, turkey, lunar, marigold

    /// The hat's frame in the art set.
    public var frameName: String { "hat_" + rawValue }

    /// The hat a date calls for: a witch hat for Halloween, a santa hat through
    /// December, a party hat at New Year, a flower crown in spring.
    public static func seasonal(on date: Date, calendar: Calendar = .current) -> PetHat? {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return nil }
        switch (month, day) {
        case (10, 17...31): return .witch
        case (12, 31), (1, 1...2): return .party
        case (12, _): return .santa
        case (3, 20...31), (4, 1...20): return .flowers
        default: return nil
        }
    }
}

/// What the fox wears on its head: the season's hat, nothing, or a favourite.
public enum PetHatChoice: String, CaseIterable, Codable, Sendable {
    case seasonal, none, party, witch, santa, flowers, hearts, shamrock, bunny, turkey, lunar, marigold

    /// The hat to draw on `date`: seasonal dresses for today's `holiday` first,
    /// then for the season.
    public func hat(on date: Date, calendar: Calendar = .current, holiday: PetHoliday? = nil) -> PetHat? {
        switch self {
        case .seasonal: return holiday?.hat ?? PetHat.seasonal(on: date, calendar: calendar)
        case .none: return nil
        default: return PetHat(rawValue: rawValue)
        }
    }

    /// The next choice when cycling through them.
    public var next: PetHatChoice {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    public var title: String {
        switch self {
        case .seasonal: return "Seasonal"
        case .none: return "No hat"
        case .party: return "Party hat"
        case .witch: return "Witch hat"
        case .santa: return "Santa hat"
        case .flowers: return "Flower crown"
        case .hearts: return "Heart bopper"
        case .shamrock: return "Shamrock hat"
        case .bunny: return "Bunny ears"
        case .turkey: return "Turkey feathers"
        case .lunar: return "Lunar New Year cap"
        case .marigold: return "Marigold crown"
        }
    }
}

public extension PetFrame {
    /// Where frame `name` wears a hat — the pixel boundary the hat centres on
    /// and the row its bottom row covers — mirrored with the frame. `nil`: no
    /// hat on this frame.
    static func hatAnchor(for name: String) -> (x: Int, y: Int)? {
        let mirrored = name.hasSuffix(mirrorSuffix)
        let base = mirrored ? String(name.dropLast(mirrorSuffix.count)) : name
        guard let anchor = PetArt.hatAnchors[base], anchor.count == 2 else { return nil }
        return (mirrored ? size - anchor[0] : anchor[0], anchor[1])
    }

    /// The runs of `hat` placed on frame `name`'s anchor, in the frame's own
    /// pixel coordinates (they may reach above row 0). Empty when the frame
    /// wears no hat or the art has none.
    static func hatRuns(_ hat: PetHat, on name: String) -> [Run] {
        guard let anchor = hatAnchor(for: name),
              let art = named(self.name(hat.frameName, mirrored: name.hasSuffix(mirrorSuffix))) else { return [] }
        return art.runs.map { Run(x: $0.x + anchor.x - 8, y: $0.y + anchor.y - 15, length: $0.length, color: $0.color) }
    }
}
