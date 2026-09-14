import SwiftUI

/// The wings' silhouette: a bar with square top corners and rounded only its
/// two OUTER bottom corners.
///
/// The wings stretch sideways from the notch, so the shape has to read as one
/// continuous piece of the notch: the top corners are square right angles (the
/// bar runs full-width into the screen's top edge, like the notch meeting the
/// bezel), the middle runs square into the notch cutout, and only the far left
/// and far right bottom corners curve. That is what makes the bar look like it
/// grew out of the notch rather than being a floating rectangle.
struct WingShape: Shape {

    /// How far the outer bottom corners curve (convex, outward).
    var bottomRadius: CGFloat

    /// The base height the radius is authored against (the notch's height).
    /// The radius scales with the CURRENT rect height so corners morph
    /// smoothly as the island stretches.
    var notchHeight: CGFloat

    init(bottomRadius: CGFloat, notchHeight: CGFloat) {
        self.bottomRadius = bottomRadius
        self.notchHeight = notchHeight
    }

    func path(in rect: CGRect) -> Path {
        // Scale the radius with the CURRENT (animated) height, not a precomputed
        // final value, so the corners morph smoothly as the island stretches.
        let scale = notchHeight > 0 ? min(2, max(1, rect.height / notchHeight)) : 1
        let br = min(bottomRadius * scale, rect.width / 2, rect.height)

        var path = Path()
        // Square across the top, into the squared top-right corner.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Down the right edge to where the outer curve begins.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        
        // Bottom-right: smooth continuous curve.
        // Using a cubic Bezier to approximate a continuous corner (G2-like).
        path.addCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - br * 0.4477),
            control2: CGPoint(x: rect.maxX - br * 0.4477, y: rect.maxY)
        )
        
        // Along the bottom edge, under the notch.
        path.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        
        // Bottom-left: smooth continuous curve.
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - br),
            control1: CGPoint(x: rect.minX + br * 0.4477, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - br * 0.4477)
        )
        
        // Up the left edge, back to the squared top-left corner.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
