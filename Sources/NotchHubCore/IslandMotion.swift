import CoreGraphics

/// The kind of motion that carries the island from one shape to the next.
///
/// The motion is derived from the before/after frames rather than chosen by
/// whoever triggered the change, so the same change always moves the same way —
/// a collapse is a collapse whether a hover exit, a tick or an event caused it.
public enum IslandMotion: String, Equatable, Sendable {
    /// Nothing visible moves: a readout's value changed in place.
    case none
    /// Emerging from the notch (idle → wings / compact / a panel).
    case peek
    /// Growing into a larger surface.
    case expand
    /// Shrinking to a smaller surface that stays visible.
    case collapse
    /// Draining back into the notch (→ idle).
    case retract
    /// Roughly the same footprint with new proportions or new content.
    case morph

    /// Relative area change below which a change reads as a morph, not a
    /// growth — a compact bar widening for a longer readout is not an "expand".
    public static let morphThreshold: CGFloat = 0.15

    public static func between(from: CGRect, fromIdle: Bool, to: CGRect, toIdle: Bool) -> IslandMotion {
        if fromIdle && toIdle {
            // Only the pet's dock changes shape while idle: it pours out of the
            // notch, drains back into it, or flows to the other side.
            guard from != to else { return .none }
            let fromArea = from.width * from.height
            let toArea = to.width * to.height
            if toArea > fromArea { return .peek }
            return toArea < fromArea ? .collapse : .morph
        }
        if toIdle { return .retract }
        if fromIdle { return .peek }
        let fromArea = from.width * from.height
        let toArea = to.width * to.height
        guard fromArea > 0 else { return .expand }
        let change = (toArea - fromArea) / fromArea
        if abs(change) < morphThreshold { return .morph }
        return change > 0 ? .expand : .collapse
    }
}
