import NotchHubCore
import SwiftUI

/// The MacBook notch's own silhouette: a tab hanging from the top of the screen.
///
/// Like the physical notch, the shape FLARES where it meets the top edge: each
/// top corner is a small concave curve sweeping outward into the screen's top
/// edge — drawn just outside the rect, so layout and hit testing are unchanged —
/// and each bottom corner is rounded outward. All four radii animate, so the
/// island reshapes continuously between states.
struct NotchShape: Shape {

    /// The bottom-left corner radius.
    var bottomLeadingRadius: CGFloat
    /// The bottom-right corner radius.
    var bottomTrailingRadius: CGFloat
    /// The top-left flare: how far the shape sweeps out left of the rect along
    /// the top edge (and down its side). `0` is a square corner.
    var topLeadingRadius: CGFloat
    /// The top-right flare.
    var topTrailingRadius: CGFloat

    init(bottomRadius: CGFloat, topRadius: CGFloat = 0) {
        self.init(bottomLeadingRadius: bottomRadius, bottomTrailingRadius: bottomRadius,
                  topLeadingRadius: topRadius, topTrailingRadius: topRadius)
    }

    init(bottomLeadingRadius: CGFloat, bottomTrailingRadius: CGFloat, topLeadingRadius: CGFloat, topTrailingRadius: CGFloat) {
        self.bottomLeadingRadius = bottomLeadingRadius
        self.bottomTrailingRadius = bottomTrailingRadius
        self.topLeadingRadius = topLeadingRadius
        self.topTrailingRadius = topTrailingRadius
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(bottomLeadingRadius, bottomTrailingRadius), AnimatablePair(topLeadingRadius, topTrailingRadius))
        }
        set {
            bottomLeadingRadius = newValue.first.first
            bottomTrailingRadius = newValue.first.second
            topLeadingRadius = newValue.second.first
            topTrailingRadius = newValue.second.second
        }
    }

    /// The island's silhouette.
    ///
    /// Every shape hangs from the top of the screen with the hardware notch's
    /// flares. The pet's idle dock CONTINUES the physical notch: BOTH sides take
    /// the notch's own flare and bottom corner — out on the dock they match the
    /// hardware, and behind it they coincide with its outline — so the two sides
    /// start (and end) every expansion and collapse from the same shape and
    /// morph identically.
    static func surface(islandRadius: CGFloat, idleDock dock: PetDock?) -> NotchShape {
        let flare = DesignTokens.radiusNotchTopFlare
        guard dock != nil else {
            return NotchShape(bottomRadius: islandRadius, topRadius: flare)
        }
        return NotchShape(bottomRadius: DesignTokens.radiusPhysicalNotchBottom, topRadius: flare)
    }

    func path(in rect: CGRect) -> Path {
        // Cubic handles for a circular quarter: 1 - 0.5523 of the radius from
        // the corner point.
        let handle: CGFloat = 0.4477
        let topLeft = max(0, min(topLeadingRadius, rect.height / 2))
        let topRight = max(0, min(topTrailingRadius, rect.height / 2))
        // Never let a bottom radius exceed half the width, or run into the flare
        // above it, or the corners would cross over on a very small surface.
        let bottomLeft = max(0, min(bottomLeadingRadius, rect.width / 2, rect.height - topLeft))
        let bottomRight = max(0, min(bottomTrailingRadius, rect.width / 2, rect.height - topRight))

        var path = Path()
        // Along the top of the screen, including both flares.
        path.move(to: CGPoint(x: rect.minX - topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + topRight, y: rect.minY))

        // Top-right flare: a concave curve down into the right edge.
        if topRight > 0 {
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + topRight),
                control1: CGPoint(x: rect.maxX + topRight * handle, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY + topRight * handle)
            )
        }

        // Down the right edge, round the bottom-right corner.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addCurve(
            to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight * handle),
            control2: CGPoint(x: rect.maxX - bottomRight * handle, y: rect.maxY)
        )

        // Along the bottom, round the bottom-left corner.
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft),
            control1: CGPoint(x: rect.minX + bottomLeft * handle, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft * handle)
        )

        // Up the left edge and out along the top-left flare.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        if topLeft > 0 {
            path.addCurve(
                to: CGPoint(x: rect.minX - topLeft, y: rect.minY),
                control1: CGPoint(x: rect.minX, y: rect.minY + topLeft * handle),
                control2: CGPoint(x: rect.minX - topLeft * handle, y: rect.minY)
            )
        }
        path.closeSubpath()
        return path
    }
}
