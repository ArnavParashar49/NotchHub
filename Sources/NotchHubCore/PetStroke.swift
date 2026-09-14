import CoreGraphics
import Foundation

/// Tells a stroke from a hover: the cursor going back and forth over the pet.
///
/// Fed the cursor's x while it is over the pet. A leg runs from where the
/// cursor turned to its furthest point; it turns only once the cursor comes
/// back `turnBack` from that point, so jitter never counts, and small moves add
/// up however finely they arrive. A stroke is two turns after real legs, close
/// together in time.
public struct PetStrokeDetector: Equatable, Sendable {
    /// How long a leg must be before its turn counts.
    public static let minimumTravel: CGFloat = 6
    /// How far the cursor must come back before a turn is a turn.
    public static let turnBack: CGFloat = 3
    /// How close together the turns must be.
    public static let window: TimeInterval = 1.2

    private var anchor: CGFloat?
    private var extreme: CGFloat = 0
    private var direction = 0
    private var reversals: [Date] = []

    public init() {}

    /// Records a cursor position; returns whether it completed a stroke.
    public mutating func move(to x: CGFloat, at now: Date) -> Bool {
        guard let start = anchor else {
            anchor = x
            extreme = x
            return false
        }
        if direction == 0 {
            guard abs(x - start) >= Self.turnBack else { return false }
            direction = x > start ? 1 : -1
            extreme = x
            return false
        }
        let heading = CGFloat(direction)
        if (x - extreme) * heading > 0 {
            extreme = x
            return false
        }
        guard (extreme - x) * heading >= Self.turnBack else { return false }
        // A real turn.
        if abs(extreme - start) >= Self.minimumTravel {
            reversals.append(now)
        }
        anchor = extreme
        extreme = x
        direction = -direction
        reversals.removeAll { now.timeIntervalSince($0) > Self.window }
        guard reversals.count >= 2 else { return false }
        // Keep the latest, so a continuing stroke counts again on its next turn.
        reversals = [reversals[reversals.count - 1]]
        return true
    }

    /// The cursor left the pet.
    public mutating func reset() {
        self = PetStrokeDetector()
    }
}
