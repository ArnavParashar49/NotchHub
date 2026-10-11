import NotchHubCore
import SwiftUI

/// The island's rim: the open U of its silhouette — down a side, round the
/// bottom corner, along the bottom — offset in or out by a few points, as the
/// exact companion of `NotchShape`.
///
/// At offset 0 it IS the silhouette's edge, curve for curve: the same clamped
/// radii, the same circular-quarter Béziers (handles 0.5523 of the radius
/// from each end, i.e. `NotchShape`'s 0.4477 from the corner). Offsets are
/// concentric with those quarters — the bottom corners' radii grow outward
/// and shrink inward, the concave top flares' the other way — so a band
/// between two offsets keeps an even width all the way round, and its
/// offset-0 edge lies exactly on the black's.
///
/// Nothing runs across the top: each half ends at the screen's top edge, at
/// the end of its flare.
struct NotchRimGeometry {
    /// The island's rect, as `NotchShape.path(in:)` gets it.
    let rect: CGRect
    let topLeading: CGFloat
    let topTrailing: CGFloat
    let bottomLeading: CGFloat
    let bottomTrailing: CGFloat

    /// A quarter circle as a cubic: each handle this fraction of the radius
    /// from its end — `1 - NotchShape`'s handle.
    static let kappa: CGFloat = 1 - 0.4477

    init(_ shape: NotchShape, in rect: CGRect) {
        self.rect = rect
        // Exactly `NotchShape.path(in:)`'s clamps, so the rim never parts
        // from the black on a small or squashed island.
        topLeading = max(0, min(shape.topLeadingRadius, rect.height / 2))
        topTrailing = max(0, min(shape.topTrailingRadius, rect.height / 2))
        bottomLeading = max(0, min(shape.bottomLeadingRadius, rect.width / 2, rect.height - topLeading))
        bottomTrailing = max(0, min(shape.bottomTrailingRadius, rect.width / 2, rect.height - topTrailing))
    }

    /// One piece of a contour: a line, or a cubic with two control points.
    struct Segment {
        var start: CGPoint
        var control1: CGPoint?
        var control2: CGPoint?
        var end: CGPoint

        var reversed: Segment { Segment(start: end, control1: control2, control2: control1, end: start) }
    }

    /// One half of the rim at `offset` (points; negative is inside the
    /// island, positive outside), from its top end to where the halves meet
    /// on the bottom edge: `split`, from the island's left (its middle when
    /// `nil`).
    func half(_ half: NeoWakeLight.Half, offset d: CGFloat, split: CGFloat? = nil) -> [Segment] {
        let leading = half == .leading
        let flare = leading ? topLeading : topTrailing
        let corner = leading ? bottomLeading : bottomTrailing
        let height = rect.height
        // Built in the half's own frame — x' measured inward from its side
        // edge — and mirrored into place for the trailing half.
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: leading ? rect.minX + x : rect.maxX - x, y: rect.minY + y)
        }
        func quarter(from a: CGPoint, corner c: CGPoint, to b: CGPoint) -> Segment {
            let k = Self.kappa
            return Segment(start: a,
                           control1: CGPoint(x: a.x + (c.x - a.x) * k, y: a.y + (c.y - a.y) * k),
                           control2: CGPoint(x: b.x + (c.x - b.x) * k, y: b.y + (c.y - b.y) * k),
                           end: b)
        }

        var segments: [Segment] = []
        // The top flare: concave, centred out over the screen at (-flare,
        // flare), so outward offsets tighten it and inward ones open it.
        var cursor: CGPoint
        if flare > 0, flare - d > 0 {
            let top = point(-flare, d)
            let side = point(-d, flare)
            segments.append(quarter(from: top, corner: point(-d, d), to: side))
            cursor = side
        } else {
            cursor = point(-d, min(0, d))
        }
        // Down the side and round the bottom corner (convex, centred inside
        // at (corner, height - corner)).
        if corner + d > 0 {
            let sideEnd = point(-d, height - corner)
            segments.append(Segment(start: cursor, end: sideEnd))
            let bottom = point(corner, height + d)
            segments.append(quarter(from: sideEnd, corner: point(-d, height + d), to: bottom))
            cursor = bottom
        } else {
            let sharp = point(-d, height + d)
            segments.append(Segment(start: cursor, end: sharp))
            cursor = sharp
        }
        // Along the bottom to the meeting point.
        segments.append(Segment(start: cursor, end: CGPoint(x: rect.minX + (split ?? rect.width / 2), y: rect.minY + height + d)))
        return segments
    }

    static func add(_ segments: [Segment], to path: inout Path, moving: Bool) {
        for (index, segment) in segments.enumerated() {
            if index == 0 {
                if moving { path.move(to: segment.start) } else { path.addLine(to: segment.start) }
            }
            if let c1 = segment.control1, let c2 = segment.control2 {
                path.addCurve(to: segment.end, control1: c1, control2: c2)
            } else {
                path.addLine(to: segment.end)
            }
        }
    }
}

/// A band along one half of the island's rim, between two offsets of its
/// silhouette: the shape NEO's wake light is drawn in.
///
/// It is drawn round `island` — the island's rect in the drawing's
/// coordinates, given rather than taken from the layout — because the
/// light is drawn from the island's in-between geometry, handed down frame
/// by frame while it springs (see `NeoWakeRim`).
struct NotchRimBand: Shape {
    let shape: NotchShape
    let island: CGRect
    let half: NeoWakeLight.Half
    /// Where the halves meet, from the island's left.
    let split: CGFloat
    /// The band's inner and outer edges: offsets from the silhouette in
    /// points, negative inside the island.
    let inner: CGFloat
    let outer: CGFloat

    func path(in _: CGRect) -> Path {
        let rim = NotchRimGeometry(shape, in: island)
        var path = Path()
        // Out along one edge to where the halves meet, back along the other,
        // and closed across the two ends: there, and at the top end, on the
        // screen's top edge.
        NotchRimGeometry.add(rim.half(half, offset: outer, split: split), to: &path, moving: true)
        NotchRimGeometry.add(rim.half(half, offset: inner, split: split).reversed().map(\.reversed), to: &path, moving: false)
        path.closeSubpath()
        return path
    }
}
