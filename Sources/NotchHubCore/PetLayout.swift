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

/// How big the pet is drawn in the notch strip.
public enum PetSize: String, CaseIterable, Codable, Sendable {
    case small, normal, large

    public var title: String {
        switch self {
        case .small: return "Small"
        case .normal: return "Normal"
        case .large: return "Large"
        }
    }

    /// The pet's side in the notch strip, in points: 14, 16 or 20. All three
    /// leave room for NEO's listening glow (the pet + 6 pt, swelling to 1.06×)
    /// inside a 32-pt strip.
    public var points: CGFloat {
        switch self {
        case .small: return 14
        case .normal: return 16
        case .large: return 20
        }
    }
}

/// Everything about the pet's place that depends on its size: how far the
/// idle dock reaches, how much room a bar keeps for it, how its art pixels and
/// its animations' offsets turn into points.
///
/// `normal` is the art's own size — one point per art pixel — and every value
/// here is then exactly `PetLayout`'s constant. The other sizes scale the same
/// geometry about the notch's edge: the art is drawn with nearest-neighbour
/// pixels (each art pixel's edges snapped to device pixels, never smoothed),
/// and every position and offset is a whole number of points, so the sprite
/// stays crisp and never shimmers as it moves.
public struct PetMetrics: Equatable, Sendable {
    public let size: PetSize

    public init(_ size: PetSize) {
        self.size = size
    }

    public static let normal = PetMetrics(.normal)

    /// The pet's side in the notch strip.
    public var side: CGFloat { size.points }
    /// Points per art pixel in the notch strip: 0.875, 1 or 1.25.
    public var scale: CGFloat { side / PetLayout.artSize }
    /// The pet's inset from the outer edge of the idle dock: 8, 9 or 11.
    public var dockInset: CGFloat { (PetLayout.dockInset * scale).rounded() }
    /// Width the pet adds to the right side of a notch-height bar.
    public var barSlot: CGFloat { side + PetLayout.gap }
    /// How far the idle island reaches out of the notch for the pet: 30, 34 or 42.
    public var idleDock: CGFloat { side + dockInset * 2 }
    /// How far the dock reaches for a peek: half the pet and a margin.
    public var peekReach: CGFloat { (side / 2).rounded(.up) + 4 }
    /// Points per art pixel in the expanded island: twice the strip's.
    public var expandedScale: CGFloat { scale * PetLayout.expandedScale }
    /// Width reserved at the right of the expanded island's content.
    public var expandedReserve: CGFloat { PetLayout.artSize * expandedScale + 14 }

    /// Rows of headroom a hat needs above the pet's frame while it stands,
    /// looks up or breathes in (an 8-row hat on the `alert` frame, lifted 1).
    static let standingHatRows: CGFloat = 6

    /// The pet's top in a notch strip `notchHeight` tall: centred — lowered,
    /// for a pet too big to wear a hat there, until a standing pet's hat fits
    /// under the top of the screen (but never onto the strip's bottom edge).
    public func stripY(notchHeight: CGFloat) -> CGFloat {
        let centred = ((notchHeight - side) / 2).rounded(.down)
        guard scale > 1 else { return centred }
        let forHat = (Self.standingHatRows * scale).rounded(.up)
        return max(centred, min(forHat, notchHeight - side - 2))
    }

    /// The brain's dock (`PetBrain.dock`, measured for the normal size) as
    /// this size's: a full dock, a peek's, closed — or in between, in proportion.
    public func dock(_ dock: PetDock) -> PetDock {
        guard size != .normal else { return dock }
        let reach: CGFloat
        if dock.reach <= 0 {
            reach = 0
        } else if dock.reach >= PetLayout.idleDock {
            reach = idleDock
        } else if dock.reach == PetLayout.peekReach {
            reach = peekReach
        } else {
            reach = (dock.reach * idleDock / PetLayout.idleDock).rounded()
        }
        return PetDock(side: dock.side, reach: reach)
    }

    /// Where the edge before art pixel `pixel` (0 … 16, or beyond for a hat's
    /// headroom) is drawn, in points from the frame's edge, on a display with
    /// `grid` device pixels per point: the nearest device pixel. Nearest-
    /// neighbour scaling — a pixel's far edge is the next one's near edge, so
    /// no pixel is ever blended, split or lost.
    public static func pixelEdge(_ pixel: CGFloat, scale: CGFloat, grid: CGFloat) -> CGFloat {
        (pixel * scale * grid).rounded() / grid
    }

    /// An animation's offset (whole art pixels) in whole points at `scale`
    /// points per art pixel, so a moving sprite always lands on the pixel grid.
    public static func points(_ pixels: Int, scale: CGFloat) -> CGFloat {
        (CGFloat(pixels) * scale).rounded()
    }
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
        /// Points per art pixel: a whole number at the normal size (1 in the
        /// strip, 2 expanded); 0.875 / 1.75 small and 1.25 / 2.5 large, drawn
        /// with nearest-neighbour pixels (`PetMetrics`).
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
    /// it (a dock shorter than the pet simply hides it). `dock` is the dock as
    /// DRAWN — for a size other than normal, `PetMetrics.dock(_:)` of the
    /// brain's.
    public static func placement(for state: IslandState, islandSize: CGSize, notchHeight: CGFloat, dock: PetDock = .home,
                                 size: PetSize = .normal) -> Placement? {
        let metrics = PetMetrics(size)
        let side = metrics.side
        let scale = metrics.scale
        let dockInset = metrics.dockInset
        let stripY = metrics.stripY(notchHeight: notchHeight)
        switch state {
        case .idle:
            switch dock.side {
            case .right:
                return Placement(origin: CGPoint(x: islandSize.width - dock.trail + dockInset, y: stripY), scale: scale, anchor: .trailing)
            case .left:
                return Placement(origin: CGPoint(x: dock.lead - dockInset - side, y: stripY), scale: scale, anchor: .leading)
            }
        case .wings:
            return Placement(origin: CGPoint(x: islandSize.width - DesignTokens.wingInset - side, y: stripY), scale: scale)
        case .compact:
            return Placement(origin: CGPoint(x: islandSize.width - DesignTokens.compactInset - side, y: stripY), scale: scale)
        case .expanded:
            let big = artSize * metrics.expandedScale
            let content = islandSize.height - notchHeight
            let y = notchHeight + ((content - big) / 2).rounded(.down)
            return Placement(origin: CGPoint(x: islandSize.width - DesignTokens.contentInset - big, y: y), scale: metrics.expandedScale)
        case .interactive:
            // In the notch strip, just left of the "···".
            let x = islandSize.width - DashboardLayout.horizontalInset - DashboardLayout.moreSize.width - gap - side
            return Placement(origin: CGPoint(x: x, y: stripY), scale: scale)
        case .appPanel:
            let x = islandSize.width - AppPanelLayout.horizontalInset - AppPanelLayout.moreSize.width - gap - side
            return Placement(origin: CGPoint(x: x, y: stripY), scale: scale)
        case .meeting:
            return Placement(origin: CGPoint(x: islandSize.width - MeetingControlLayout.contentInset - side, y: stripY), scale: scale)
        case .neoConfirm:
            // In the strip beside the notch, exactly where it stands on its
            // idle dock (the surface reaches one NORMAL dock beyond the notch
            // on each side, whatever the pet's size — a large pet still fits
            // in it): the buttons come out under the notch and the pet, in
            // its "!" pose, does not move.
            switch dock.side {
            case .right:
                return Placement(origin: CGPoint(x: islandSize.width - idleDock + dockInset, y: stripY), scale: scale, anchor: .trailing)
            case .left:
                return Placement(origin: CGPoint(x: idleDock - dockInset - side, y: stripY), scale: scale, anchor: .leading)
            }
        // Utility surfaces the pet steps aside for: a teleprompter with a fox
        // in it is a fox in the way, and the camera's picture is the content.
        case .tray, .settings, .fileDrop, .skin,
             .teleprompter, .teleprompterCompose, .camera, .cameraExpanded, .neoPanel:
            return nil
        }
    }
}
