import CoreGraphics

/// A side of the notch.
public enum PetSide: String, Equatable, Sendable {
    case left, right

    public var opposite: PetSide { self == .left ? .right : .left }
}

/// The idle island's home for the pet beside the notch: which side of the notch
/// the pet is on, and how far the black dock reaches out of the notch there.
///
/// `PetBrain` moves it (hiding in the notch, peeking out, visiting the other
/// side); `NotchGeometry` shapes the idle island from it; `PetLayout` places
/// the pet in it.
public struct PetDock: Equatable, Sendable {
    public var side: PetSide
    /// Points the dock reaches beyond the notch: `PetLayout.idleDock` at home,
    /// `PetLayout.peekReach` for a peek, `0` while the pet hides in the notch.
    public var reach: CGFloat

    public init(side: PetSide, reach: CGFloat) {
        self.side = side
        self.reach = reach
    }

    /// Sitting beside the notch on the right — where the pet lives.
    public static let home = PetDock(side: .right, reach: PetLayout.idleDock)

    /// How far the idle island reaches left of the notch.
    public var lead: CGFloat { side == .left ? max(0, reach) : 0 }
    /// How far the idle island reaches right of the notch.
    public var trail: CGFloat { side == .right ? max(0, reach) : 0 }
}

/// Where the pet lives inside each island shape.
///
/// Placements are relative to the island's own frame (top-left origin) and are
/// measured from the edge the pet belongs to — the RIGHT edge everywhere except
/// the idle dock on the left of the notch — so when the island's width springs,
/// the pet rides the same spring instead of jumping. Widths the pet needs are
/// added to the content measurement, so it never overlaps activity content.
public enum PetLayout {

    /// Art pixels per side.
    public static let artSize: CGFloat = CGFloat(PetFrame.size)
    /// Space between the pet and the content beside it.
    public static let gap: CGFloat = 6
    /// The pet's inset from the outer edge of the idle dock.
    public static let dockInset: CGFloat = 9

    /// Width the pet adds to the right side of a notch-height bar (wings,
    /// compact) — the bar's own trailing inset stays outside the pet.
    public static var barSlot: CGFloat { artSize + gap }

    /// How far the idle island reaches out of the physical notch to give the
    /// pet a home: `[ notch ][pet]`.
    public static var idleDock: CGFloat { artSize + dockInset * 2 }

    /// How far the pet moves from its dock spot toward the notch to be wholly
    /// hidden by the physical notch, in whole points.
    public static let hiddenOffset = -(Int(dockInset) + PetFrame.size + 3)

    /// Where a peek frame is drawn: its columns 0–7 under the notch, 8–15 out.
    public static let peekOffset = -(Int(dockInset) + PetFrame.size / 2)

    /// How far the dock reaches for a peek: the eight peeking columns and a
    /// margin before the dock's rounded corner.
    public static let peekReach: CGFloat = CGFloat(PetFrame.size / 2) + 4

    /// Pixel scale in the expanded island ("slightly larger").
    public static let expandedScale: CGFloat = 2

    /// Width reserved at the right of the expanded island's content for the
    /// larger pet.
    public static var expandedReserve: CGFloat { artSize * expandedScale + 14 }

    /// The island edge a placement is measured from.
    public enum Anchor: Equatable, Sendable {
        case leading, trailing
    }

    public struct Placement: Equatable, Sendable {
        /// Top-left of the pet, in the island's coordinates.
        public var origin: CGPoint
        /// Points per art pixel — always a whole number, so pixels stay crisp.
        public var scale: CGFloat
        /// The edge the pet travels with while the island resizes.
        public var anchor: Anchor = .trailing

        public var size: CGFloat { artSize * scale }
    }

    /// The pet's placement for an island shape, or `nil` where the pet steps
    /// aside (utility panels: the Tray, settings, the file drop).
    ///
    /// Idle places the pet beside the notch on the dock's side, measured from
    /// the NOTCH edge, so it stays put while its dock grows and shrinks around
    /// it (a dock shorter than the pet simply hides it).
    public static func placement(for state: IslandState, islandSize: CGSize, notchHeight: CGFloat, dock: PetDock = .home) -> Placement? {
        let stripY = ((notchHeight - artSize) / 2).rounded(.down)
        switch state {
        case .idle:
            switch dock.side {
            case .right:
                return Placement(origin: CGPoint(x: islandSize.width - dock.trail + dockInset, y: stripY), scale: 1, anchor: .trailing)
            case .left:
                return Placement(origin: CGPoint(x: dock.lead - dockInset - artSize, y: stripY), scale: 1, anchor: .leading)
            }
        case .wings:
            return Placement(origin: CGPoint(x: islandSize.width - DesignTokens.wingInset - artSize, y: stripY), scale: 1)
        case .compact:
            return Placement(origin: CGPoint(x: islandSize.width - DesignTokens.compactInset - artSize, y: stripY), scale: 1)
        case .expanded:
            let size = artSize * expandedScale
            let content = islandSize.height - notchHeight
            let y = notchHeight + ((content - size) / 2).rounded(.down)
            return Placement(origin: CGPoint(x: islandSize.width - DesignTokens.contentInset - size, y: y), scale: expandedScale)
        case .interactive:
            // In the notch strip, just left of the "···".
            let x = islandSize.width - DashboardLayout.horizontalInset - DashboardLayout.moreSize.width - gap - artSize
            return Placement(origin: CGPoint(x: x, y: stripY), scale: 1)
        case .appPanel:
            let x = islandSize.width - AppPanelLayout.horizontalInset - AppPanelLayout.moreSize.width - gap - artSize
            return Placement(origin: CGPoint(x: x, y: stripY), scale: 1)
        case .meeting:
            return Placement(origin: CGPoint(x: islandSize.width - MeetingControlLayout.contentInset - artSize, y: stripY), scale: 1)
        // Utility surfaces the pet steps aside for: a teleprompter with a fox
        // in it is a fox in the way, and the camera's picture is the content.
        case .tray, .settings, .fileDrop, .skin,
             .teleprompter, .teleprompterCompose, .camera, .cameraExpanded:
            return nil
        }
    }
}
