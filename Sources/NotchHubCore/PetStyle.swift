import Foundation

/// Who the pet is: the fox in the notch is NEO, the voice assistant — its
/// poses are what NEO is doing (`PetBrain.neoAnimation`).
public enum PetIdentity {
    /// The fox's name, until the user gives it another (`PetSettings.name`).
    /// NEO the assistant is always "NEO"; only the pet's display name changes.
    public static let name = "Neo"
    /// What it says when its panel opens (a holiday greeting takes its place).
    public static var hello: String { hello(name: name) }
    /// The hello of a pet called `name`.
    public static func hello(name: String) -> String { "Hi, I'm \(name)!" }

    /// The longest name the pet can be given, in characters.
    public static let maxNameLength = 16

    /// A name as the pet can carry it: trimmed, on one line, at most
    /// `maxNameLength` characters — and "Neo" when nothing is left.
    public static func validName(_ raw: String) -> String {
        let oneLine = raw.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(trimmed.prefix(maxNameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? name : cut
    }
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
    case red
    case midnight
    case snow
    case cocoa
    case sakura
    case cyber

    public var title: String {
        switch self {
        case .fox: return "Fox"
        case .arctic: return "Arctic"
        case .silver: return "Silver"
        case .sand: return "Sand"
        case .red: return "Red"
        case .midnight: return "Midnight"
        case .snow: return "Snow"
        case .cocoa: return "Cocoa"
        case .sakura: return "Sakura"
        case .cyber: return "Cyber"
        }
    }

    /// Base colour → this look's colour (empty for the fox: the art's own).
    public var colorMap: [UInt32: UInt32] { Self.maps[self] ?? [:] }

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

/// What the fox wears besides a hat (`art/pet/wear.pet`): one accessory at a
/// time, together with any hat. Drawn on each frame's wear anchor
/// (`art/pet/wear.txt`), over the fox and under the hat.
public enum PetAccessory: String, CaseIterable, Codable, Sendable {
    case glasses, sunglasses, scarf, bowtie, headphones

    /// The part of the fox an accessory is worn on. A frame can hide a slot
    /// (a clock held in front of the chest hides what is worn at the neck).
    public enum Slot: Int, Sendable {
        case face, neck, ears
    }

    public var slot: Slot {
        switch self {
        case .glasses, .sunglasses: return .face
        case .scarf, .bowtie: return .neck
        case .headphones: return .ears
        }
    }

    /// The accessory's front-view frame in the art set.
    public var frameName: String { "acc_" + rawValue }
    /// Its side-view frame (the fox in profile, facing left).
    public var sideFrameName: String { frameName + "_side" }

    public var title: String {
        switch self {
        case .glasses: return "Glasses"
        case .sunglasses: return "Sunglasses"
        case .scarf: return "Scarf"
        case .bowtie: return "Bow tie"
        case .headphones: return "Headphones"
        }
    }
}

/// The accessory slot in the settings: nothing, or one accessory.
public enum PetAccessoryChoice: String, CaseIterable, Codable, Sendable {
    case none, glasses, sunglasses, scarf, bowtie, headphones

    public var accessory: PetAccessory? { PetAccessory(rawValue: rawValue) }

    public var title: String { accessory?.title ?? "None" }
}

public extension PetFrame {
    /// How a frame wears accessories.
    struct WearAnchor: Equatable, Sendable {
        public enum View: Int, Sendable {
            /// Facing the viewer: the front art, as drawn on `sit`.
            case front
            /// In profile facing left: the side art, as drawn on `run_1`.
            case side
            /// Leaning out of the notch facing right: the side art mirrored.
            case peek
        }

        public var view: View
        /// The pixel boundary at the middle of the head.
        public var x: Int
        /// The row of the head's top outline between the ears.
        public var y: Int
        /// Slots a prop covers on this frame.
        public var hidden: Set<PetAccessory.Slot>
    }

    /// The wear anchors of the frames the accessory art is drawn on.
    static let frontWearReference = (x: 7, y: 3)
    static let sideWearReference = (x: 6, y: 3)

    /// How the UNMIRRORED frame `name` wears accessories; `nil`: it wears none.
    static func wearAnchor(for name: String) -> WearAnchor? {
        let base = name.hasSuffix(mirrorSuffix) ? String(name.dropLast(mirrorSuffix.count)) : name
        guard let raw = PetArt.wearAnchors[base], raw.count == 4, let view = WearAnchor.View(rawValue: raw[0]) else { return nil }
        let hidden = Set([PetAccessory.Slot.face, .neck, .ears].filter { raw[3] & (1 << $0.rawValue) != 0 })
        return WearAnchor(view: view, x: raw[1], y: raw[2], hidden: hidden)
    }

    /// The runs of `accessory` as frame `name` wears it, in the frame's own
    /// pixel coordinates — always INSIDE the 16×16 frame: whatever would fall
    /// outside is clipped, so an accessory never draws beyond the pet. Empty
    /// when the frame wears none (no head in it, or a prop covers the slot).
    /// Built once per accessory and frame.
    static func accessoryRuns(_ accessory: PetAccessory, on name: String) -> [Run] {
        accessoryTable[accessory]?[name] ?? []
    }

    private static let accessoryTable: [PetAccessory: [String: [Run]]] = {
        var table: [PetAccessory: [String: [Run]]] = [:]
        for accessory in PetAccessory.allCases {
            var frames: [String: [Run]] = [:]
            for name in PetArt.wearAnchors.keys {
                let runs = placedAccessory(accessory, on: name)
                guard !runs.isEmpty else { continue }
                frames[name] = runs
                frames[name + mirrorSuffix] = runs.map {
                    Run(x: size - $0.x - $0.length, y: $0.y, length: $0.length, color: $0.color)
                }
            }
            table[accessory] = frames
        }
        return table
    }()

    private static func placedAccessory(_ accessory: PetAccessory, on base: String) -> [Run] {
        guard let anchor = wearAnchor(for: base), !anchor.hidden.contains(accessory.slot) else { return [] }
        let art: PetFrame?
        let dx: Int
        let dy: Int
        switch anchor.view {
        case .front:
            art = all[accessory.frameName]
            dx = anchor.x - frontWearReference.x
            dy = anchor.y - frontWearReference.y
        case .side:
            art = all[accessory.sideFrameName]
            dx = anchor.x - sideWearReference.x
            dy = anchor.y - sideWearReference.y
        case .peek:
            art = all[accessory.sideFrameName]?.mirrored
            dx = anchor.x - (size - sideWearReference.x)
            dy = anchor.y - sideWearReference.y
        }
        guard let art else { return [] }
        return art.runs.compactMap { run in
            let y = run.y + dy
            guard y >= 0, y < size else { return nil }
            let minX = max(0, run.x + dx)
            let maxX = min(size, run.x + dx + run.length)
            guard maxX > minX else { return nil }
            return Run(x: minX, y: y, length: maxX - minX, color: run.color)
        }
    }
}
