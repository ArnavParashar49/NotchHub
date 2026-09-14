import CoreGraphics

/// The geometry of the live-call control row.
///
/// `MeetingView` draws the buttons and the window hit-tests clicks against
/// them — the island never takes key focus during a call, so SwiftUI's own
/// button handling never sees the click. Both sides read these numbers so a
/// button cannot draw in one place and accept clicks in another.
public enum MeetingControlLayout {

    /// Horizontal inset of the panel's content.
    public static let contentInset: CGFloat = 18
    /// Height of the header row (the app glyph, title and call timer).
    public static let headerHeight: CGFloat = 40
    /// Gap between the header and the control row.
    public static let rowSpacing: CGFloat = 16
    /// Side of each square control button.
    public static let buttonSize: CGFloat = 40
    /// Gap between neighbouring buttons on the leading side.
    public static let buttonSpacing: CGFloat = 12

    /// The control buttons for a meeting panel frame in AppKit coordinates
    /// (origin bottom-left). Content starts below the notch cutout, which
    /// occupies the top `notchInset` points of the panel.
    public static func buttons(in frame: CGRect, notchInset: CGFloat) -> [(control: MeetingControl, rect: CGRect)] {
        let top = frame.maxY - notchInset
        let y = top - headerHeight - rowSpacing - buttonSize
        let mute = CGRect(x: frame.minX + contentInset, y: y, width: buttonSize, height: buttonSize)
        let camera = mute.offsetBy(dx: buttonSize + buttonSpacing, dy: 0)
        let leave = CGRect(x: frame.maxX - contentInset - buttonSize, y: y, width: buttonSize, height: buttonSize)
        return [(.mute, mute), (.camera, camera), (.leave, leave)]
    }

    /// The control under a point, or `nil` for a miss. Two points of slop, as
    /// with the transport buttons.
    public static func control(at point: CGPoint, in frame: CGRect, notchInset: CGFloat) -> MeetingControl? {
        buttons(in: frame, notchInset: notchInset)
            .first { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }?
            .control
    }
}
