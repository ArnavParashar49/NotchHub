import Foundation

/// Decides which backlight readings are worth showing.
///
/// Brightness is polled, and with auto-brightness or True Tone the backlight
/// drifts by fractions of a percent almost constantly. Reporting every
/// difference made the island announce the brightness again and again. A
/// deliberate change — a brightness key (a 1/16 step), the Control Center
/// slider — moves the level by a real step between two polls, so only that is
/// reported. The first reading merely seeds the baseline, so launching (or
/// rebuilding the monitor after a settings change) never announces the
/// current level.
public struct BrightnessChangeFilter: Sendable {

    /// The smallest change between two consecutive readings that counts as
    /// deliberate. Ambient drift stays well below it; a key press (6.25%) does not.
    public static let minimumStep: Double = 0.02

    private var previous: Double?

    public init() {}

    /// Feeds one reading (0…1). Returns the level to report, or `nil`.
    public mutating func accept(_ reading: Double) -> Double? {
        let level = max(0, min(1, reading))
        defer { previous = level }
        guard let previous else { return nil }
        return abs(level - previous) >= Self.minimumStep ? level : nil
    }
}
