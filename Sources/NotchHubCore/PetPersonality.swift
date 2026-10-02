import Foundation

/// Which side of the notch the pet lives on.
public enum PetHome: String, CaseIterable, Codable, Sendable {
    /// To the right of the notch; its games take it left and it comes back.
    case right
    /// To the left of the notch; its games take it right and it comes back.
    case left
    /// No fixed home: it stays on whichever side its games leave it.
    case auto

    public var title: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        case .auto: return "Auto"
        }
    }

    /// The side it starts on.
    public var side: PetSide { self == .left ? .left : .right }
}

/// How lively the pet is. `normal` is the pet as it always was; the others
/// scale how often it fidgets (idle flourishes), how often it plays
/// (mischief), and how soon it dozes off when nothing happens.
public enum PetEnergy: String, CaseIterable, Codable, Sendable {
    /// Mostly sits and breathes: rare, quiet flourishes; mischief seldom; an
    /// early nap.
    case calm
    case normal
    /// Fidgets and plays more than twice as often, and stays up longer.
    case playful

    public var title: String {
        switch self {
        case .calm: return "Calm"
        case .normal: return "Normal"
        case .playful: return "Playful"
        }
    }

    /// Multiplies the wait between idle flourishes.
    public var flourishPace: Double {
        switch self {
        case .calm: return 2.2
        case .normal: return 1
        case .playful: return 0.55
        }
    }

    /// Multiplies the wait before, and between, bits of mischief.
    public var mischiefPace: Double {
        switch self {
        case .calm: return 3.5
        case .normal: return 1
        case .playful: return 0.4
        }
    }

    /// How long nothing must happen before it falls asleep.
    public var sleepAfter: TimeInterval {
        switch self {
        case .calm: return 90
        case .normal: return PetBrain.sleepAfter
        case .playful: return 360
        }
    }
}

/// The hours the pet sleeps through: from `startHour` up to (not including)
/// `endHour`, on the clock of the calendar it is asked with. A night whose end
/// is not after its start runs past midnight (22 → 7); equal hours are no
/// night at all.
public struct PetNight: Equatable, Sendable {
    public var startHour: Int
    public var endHour: Int

    public init(startHour: Int, endHour: Int) {
        self.startHour = Self.hour(startHour)
        self.endHour = Self.hour(endHour)
    }

    /// An hour on the clock, 0–23.
    public static func hour(_ value: Int) -> Int {
        min(23, max(0, value))
    }

    /// Whether `hour` (0–23) falls in the night.
    public func contains(hour: Int) -> Bool {
        if startHour == endHour { return false }
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        contains(hour: calendar.component(.hour, from: date))
    }

    /// The next time the night begins or ends after `date` — when the pet's
    /// state next changes on the clock alone. `nil` for a night that never is.
    public func nextChange(after date: Date, calendar: Calendar = .current) -> Date? {
        guard startHour != endHour else { return nil }
        let candidates = [startHour, endHour].compactMap { hour in
            calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: 0, second: 0),
                              matchingPolicy: .nextTime, direction: .forward)
        }
        return candidates.min()
    }

    /// "22:00 – 07:00".
    public var label: String {
        String(format: "%02d:00 – %02d:00", startHour, endHour)
    }
}
