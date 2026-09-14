import CoreGraphics

/// The geometry of the now-playing transport cluster.
///
/// The cluster is drawn by `IslandView` and hit-tested by the window, and the
/// two must agree exactly — a button that draws in one place and accepts
/// clicks in another is the classic bug this type exists to prevent. Both read
/// these numbers, and the layout is pure and unit-tested so a change to the
/// cluster's size cannot silently desynchronise them.
public enum MediaControlLayout {

    /// Diameter of the skip buttons.
    public static let secondaryDiameter: CGFloat = 24
    /// Diameter of the solid play/pause puck.
    public static let primaryDiameter: CGFloat = 28
    /// Gap between neighbouring buttons.
    public static let spacing: CGFloat = 2
    /// Padding between the buttons and the capsule's edge.
    public static let padding: CGFloat = 3
    /// Inset from the island's trailing edge, matching the content padding the
    /// expanded surface lays its content out with.
    public static let contentInset: CGFloat = 20

    /// Full size of the capsule around the three buttons.
    public static var clusterSize: CGSize {
        let width = secondaryDiameter + primaryDiameter + secondaryDiameter
            + spacing * 2
            + padding * 2
        let height = max(primaryDiameter, secondaryDiameter) + padding * 2
        return CGSize(width: width, height: height)
    }

    /// Where the cluster sits for a given island frame, and the rect of each
    /// button within it.
    ///
    /// `islandFrame` is in the hosting window's coordinate space, top-left
    /// origin — the same space AppKit reports a click in once converted, so the
    /// hit test needs no further translation.
    public struct Placement: Equatable {
        public var cluster: CGRect
        /// The three buttons, in left-to-right order.
        public var buttons: [(command: MediaCommand, rect: CGRect)]

        public static func == (lhs: Placement, rhs: Placement) -> Bool {
            lhs.cluster == rhs.cluster
                && lhs.buttons.map(\.command) == rhs.buttons.map(\.command)
                && lhs.buttons.map(\.rect) == rhs.buttons.map(\.rect)
        }
    }

    /// The command under a point, or `nil` when the point misses every button.
    ///
    /// The buttons are circles, so the test is a radius check rather than a
    /// rectangle containment — otherwise the corners of a button's box would
    /// swallow clicks that visually land on the capsule between buttons.
    public static func command(at point: CGPoint, in placement: Placement) -> MediaCommand? {
        for button in placement.buttons {
            let centre = CGPoint(x: button.rect.midX, y: button.rect.midY)
            let radius = button.rect.width / 2
            // A couple of points of slop: the glyphs are small and a click that
            // lands just outside the puck should still register.
            let hitRadius = radius + 2
            let dx = point.x - centre.x
            let dy = point.y - centre.y
            if (dx * dx + dy * dy) <= hitRadius * hitRadius {
                return button.command
            }
        }
        return nil
    }

    /// Computes the cluster's placement inside an island frame in AppKit
    /// coordinates (origin bottom-left).
    ///
    /// When `notchInset` > 0, the content is vertically centred within the
    /// visible area below the notch cutout (which occupies the top `notchInset`
    /// of the island) rather than across the full height of the island.
    /// `trailingReserve` is room kept free at the right edge (the pixel pet).
    public static func placement(in islandFrame: CGRect, notchInset: CGFloat = 0, trailingReserve: CGFloat = 0) -> Placement {
        let size = clusterSize
        // In AppKit (y=0 at bottom), the visible area below the notch is from
        // y = islandFrame.minY to y = islandFrame.maxY - notchInset.
        let visibleMidY = islandFrame.minY + (islandFrame.height - notchInset) / 2
        let cluster = CGRect(
            x: islandFrame.maxX - contentInset - trailingReserve - size.width,
            y: visibleMidY - size.height / 2,
            width: size.width,
            height: size.height
        )

        var buttons: [(MediaCommand, CGRect)] = []
        var x = cluster.minX + padding
        for (command, diameter) in [
            (MediaCommand.previous, secondaryDiameter),
            (MediaCommand.togglePlayPause, primaryDiameter),
            (MediaCommand.next, secondaryDiameter),
        ] {
            let rect = CGRect(
                x: x,
                y: cluster.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            buttons.append((command, rect))
            x += diameter + spacing
        }

        return Placement(cluster: cluster, buttons: buttons)
    }
}
