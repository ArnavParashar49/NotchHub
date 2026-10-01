import Foundation

/// Whether the island is visible to screen capture.
///
/// macOS lets a window opt out of being captured (`NSWindow.sharingType`). A
/// window set to `.none` is drawn on the physical display but is **omitted from
/// every capture path** — screen sharing in a call, QuickTime and Screenshot
/// recordings, ⇧⌘3/4/5, and any app using ScreenCaptureKit. The person at the
/// Mac still sees it; nobody on the other end of the call does.
///
/// Two separate things decide it, and they are deliberately not the same
/// switch:
///
/// - **The user's Ghost Mode setting**, which hides the whole island.
/// - **Surfaces that are ALWAYS private**, whatever that setting says. The
///   teleprompter is the obvious one: a teleprompter everybody can read is not
///   a teleprompter. It must not depend on the user having remembered to turn
///   something on before the call started.
public enum GhostMode {

    /// Island surfaces that are never shown to screen capture, regardless of
    /// the Ghost Mode setting.
    ///
    /// The test is "would the user be embarrassed, or the surface useless, if
    /// the room could see it?":
    ///
    /// - the teleprompter and its compose view — the script IS the point, and a
    ///   script the room can read is not a teleprompter;
    /// - the camera preview — you open it to check yourself before a call, and
    ///   a picture-in-picture of your own face appearing inside the screen you
    ///   are sharing is never what you meant.
    ///
    /// None of these should depend on having remembered to arm Ghost Mode
    /// before the call started.
    public static let alwaysPrivate: Set<IslandState> = [
        .teleprompter, .teleprompterCompose, .camera, .cameraExpanded,
    ]

    /// Whether the window should be hidden from capture right now.
    ///
    /// - Parameters:
    ///   - state: the shape the island is currently in.
    ///   - ghostModeEnabled: the user's own setting.
    public static func hidesFromCapture(state: IslandState, ghostModeEnabled: Bool) -> Bool {
        ghostModeEnabled || alwaysPrivate.contains(state)
    }

    /// Why the island is hidden, for the settings panel to explain.
    public static func reason(state: IslandState, ghostModeEnabled: Bool) -> Reason? {
        if alwaysPrivate.contains(state) { return .alwaysPrivateSurface }
        return ghostModeEnabled ? .ghostMode : nil
    }

    public enum Reason: Equatable, Sendable {
        /// The user turned Ghost Mode on.
        case ghostMode
        /// This surface is private whatever the setting says.
        case alwaysPrivateSurface
    }
}
