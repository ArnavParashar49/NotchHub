import AppKit
import NotchHubCore

/// Ghost Mode: keeping the island out of screen shares and recordings.
///
/// Two independent reasons a surface is hidden, and the island must honour
/// whichever applies:
///
/// - **The user turned Ghost Mode on.** Everything the island draws is then
///   invisible to capture, for as long as it is on.
/// - **The surface is private by nature.** The teleprompter is hidden whether
///   or not Ghost Mode is on, because a script the room can read is not a
///   teleprompter — and nobody should have to remember to arm that before a
///   call starts.
///
/// The hiding is done by macOS, not by the app: `NSWindow.sharingType = .none`
/// takes the window out of every capture path while leaving it on the display.
/// The app never draws anything different, so there is no frame in which the
/// island could leak into a recording.
extension NotchHubApp {

    /// Whether the user's Ghost Mode setting is on.
    var ghostModeEnabled: Bool { featureSettings.isEnabled(.ghostMode) }

    /// Whether the island is currently hidden from capture.
    var isHiddenFromCapture: Bool { window?.hidesFromCapture ?? false }

    /// Brings the window's capture visibility in line with the shape it is
    /// about to draw.
    ///
    /// Called from `renderIsland` BEFORE the new shape is applied, so a surface
    /// that must not be captured is already out of the capture path by the time
    /// its first frame exists. Setting it afterwards would leave exactly one
    /// frame of the teleprompter in the recording.
    ///
    /// `--neo-capturable` (a debug run) overrides both reasons: the window is
    /// left capturable in every shape, so a screenshot of the notch strip can
    /// show what the user sees. In memory only.
    func applyGhostMode(for state: IslandState) {
        window.hidesFromCapture = !capturableForDebug && GhostMode.hidesFromCapture(
            state: state,
            ghostModeEnabled: ghostModeEnabled
        )
    }

    /// Turns Ghost Mode on or off and applies it at once.
    func toggleGhostMode() {
        var settings = featureSettings
        settings.setEnabled(.ghostMode, enabled: !ghostModeEnabled)
        featureSettings = settings
        featureSettings.save()
        // Keep the settings panel's own snapshot in step, so opening it later
        // does not write the old value back.
        settingsModel.ghostMode = ghostModeEnabled
        log("ghost: \(ghostModeEnabled ? "on" : "off")")
        // Ghost Mode changes no listeners, so the island only has to re-render
        // — but it must re-render, to apply the new sharing type immediately
        // rather than at whatever the next event happens to be.
        renderIsland()
        if panel == .settings { refreshPanel() }
    }
}
