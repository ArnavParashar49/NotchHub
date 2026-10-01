import CoreGraphics

/// Where a mouse event is, in the island window's own coordinates.
///
/// A mouse move reaches the window two ways. Through the window itself — its
/// tracking area, or the local event monitor while the cursor is over it —
/// the location is relative to the window. Through a monitor while the
/// cursor is elsewhere, AppKit's `locationInWindow` is relative to whatever
/// window the event has: another app's (the global monitor), or NONE — the
/// local monitor, while NotchHub is the active app and the cursor is outside
/// its window — and with no window the location is in SCREEN coordinates.
///
/// Taken as window-local, such a point lies hundreds of points from the
/// cursor. After a panel (NEO's, settings, the Tray) had made NotchHub the
/// active app and closed, every move of the mouse across the screen was read
/// this way, and one that happened to map onto the notch opened the wings
/// with the mouse nowhere near them. Converting through the event's window
/// (or from the screen when it has none) puts the point where the cursor is.
public enum MouseLocation {

    /// The event's location in the island window.
    ///
    /// - Parameters:
    ///   - location: the event's `locationInWindow`.
    ///   - eventWindowFrame: the frame of the window the event belongs to, or
    ///     `nil` when it has none (then `location` is in screen coordinates).
    ///   - windowFrame: the island window's frame, in screen coordinates.
    public static func inWindow(_ location: CGPoint, eventWindowFrame: CGRect?, windowFrame: CGRect) -> CGPoint {
        let screen: CGPoint
        if let eventWindowFrame {
            if eventWindowFrame.origin == windowFrame.origin {
                return location // our own window: already local
            }
            screen = CGPoint(x: location.x + eventWindowFrame.minX, y: location.y + eventWindowFrame.minY)
        } else {
            screen = location
        }
        return CGPoint(x: screen.x - windowFrame.minX, y: screen.y - windowFrame.minY)
    }
}
