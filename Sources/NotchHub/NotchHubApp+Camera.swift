import AppKit
import NotchHubCore
import NotchHubSystem
import SwiftUI

/// The mini camera: a live preview in the notch, for the moment before a call.
///
/// The camera is never on because a panel is open — it is on because
/// `CameraController.phase` says so, and closing the panel by ANY route (the ×,
/// Esc, the hotkey, another panel taking the island, the app quitting) goes
/// through `closeCamera`, which tears the session down. That is the whole
/// safety property: there is no path that hides the preview and leaves the
/// camera running.
extension NotchHubApp {

    /// The shape the camera takes right now.
    var cameraIslandState: IslandState {
        cameraState.isExpanded ? .cameraExpanded : .camera
    }

    /// Opens the camera, or closes it if it is already showing.
    func toggleCamera() {
        if panel == .camera {
            closeCamera()
            return
        }
        guard featureSettings.isEnabled(.camera) else {
            log("camera: disabled by settings")
            return
        }
        takePanel(.camera)
        camera.open()
        log("camera: open")
        refreshPanel()
    }

    /// Closes the preview AND releases the camera. Never one without the other.
    func closeCamera() {
        guard panel == .camera else {
            // Belt and braces: if the session is somehow live with no panel, it
            // still gets stopped.
            if camera.isRunning { camera.close() }
            return
        }
        camera.close()
        closePanel()
        log("camera: closed")
    }

    /// The controller reported a new state.
    func cameraChanged(_ state: CameraState) {
        let wasExpanded = cameraState.isExpanded
        cameraState = state
        guard panel == .camera else { return }
        // A change of size is a change of island SHAPE, so it has to go through
        // a full render to pick up the new frame and spring to it; everything
        // else only re-draws the panel's content.
        if state.isExpanded != wasExpanded {
            renderIsland()
        } else {
            refreshPanel()
        }
    }

    func cameraContent() -> AnyView {
        AnyView(CameraView(state: cameraState, previewLayer: camera.previewLayer))
    }

    /// NEO owns capture and analysis; NotchHub only paints its latest frame in
    /// the native camera layout. No second capture session is started here.
    func neoCameraPresentationState() -> CameraState {
        let status = neoCameraState?.status ?? "starting"
        let phase: CameraPhase = status == "starting" ? .starting : .live
        let name = status == "analysing" ? "NEO is looking…" : "NEO camera"
        return CameraState(
            phase: phase,
            devices: [CameraDevice(id: "neo", name: name)],
            deviceID: "neo",
            isExpanded: neoCameraExpanded,
            isMirrored: neoCameraMirrored
        )
    }

    func neoCameraContent() -> AnyView {
        let state = neoCameraPresentationState()
        let caption = neoCameraState?.answer ?? neoCameraState?.labels.prefix(4).joined(separator: " · ")
        return AnyView(CameraView(
            state: state,
            previewLayer: nil,
            stream: neoCameraStream,
            caption: caption
        ))
    }

    /// Handles a click on the camera's controls. A miss falls through to the
    /// island click.
    func cameraControlHit(at point: NSPoint) -> Bool {
        if panel == .neoCamera {
            let state = neoCameraPresentationState()
            let frame = window.localFrame(for: neoCameraExpanded ? .cameraExpanded : .camera, content: .default)
            guard let action = CameraLayout.action(at: point, in: frame, state: state) else { return false }
            log("neo camera: \(action)")
            switch action {
            case .toggleSize:
                neoCameraExpanded.toggle()
                renderIsland()
            case .toggleMirror:
                neoCameraMirrored.toggle()
                refreshPanel()
            case .close:
                closePanel() // releaseCurrentPanel sends camera_stop + view-off
            case .switchDevice, .openSettings:
                break
            }
            return true
        }
        guard panel == .camera else { return false }
        let frame = window.localFrame(for: cameraIslandState, content: .default)
        guard let action = CameraLayout.action(at: point, in: frame, state: cameraState) else { return false }
        log("camera: \(action)")
        switch action {
        case .toggleSize:
            camera.toggleSize()
        case .toggleMirror:
            camera.toggleMirror()
        case .switchDevice:
            camera.switchDevice()
        case .close:
            closeCamera()
        case .openSettings:
            if let url = URL(string: CameraLayout.settingsURL) {
                NSWorkspace.shared.open(url)
            }
            closeCamera()
        }
        return true
    }
}
