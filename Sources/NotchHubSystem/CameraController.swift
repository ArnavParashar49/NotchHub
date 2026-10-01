import AppKit
@preconcurrency import AVFoundation
import NotchHubCore

/// The camera preview: a live picture in the notch, and nothing else.
///
/// It captures no frames of its own — there is a `AVCaptureVideoPreviewLayer`
/// on the session and nothing reading buffers — so the preview genuinely cannot
/// record anything. The layer is handed to the view, which owns nothing.
///
/// **The session is stopped and torn down completely on close.** Not paused,
/// not hidden: the inputs are removed and the session is released, so the
/// camera's indicator light goes out and macOS stops listing NotchHub as using
/// it. A preview that keeps the camera warm "in case" is exactly the thing
/// people are right to be suspicious of.
///
/// Everything here lives on the main actor, and `phase` is the single truth
/// about whether the camera is on — never a panel being open.
@MainActor
public final class CameraController {

    private let emit: @MainActor (CameraState) -> Void
    private var state = CameraState()

    private var session: AVCaptureSession?
    private var input: AVCaptureDeviceInput?
    /// The layer the view shows. Created with the session and destroyed with it.
    public private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    /// Starting a session blocks — it negotiates with the device — so it runs
    /// off the main thread. Only the AVFoundation calls go here; every piece of
    /// state stays on the main actor.
    private let sessionQueue = DispatchQueue(label: "notchhub.camera.session", qos: .userInitiated)

    /// The camera kinds worth offering: the built-in FaceTime camera, anything
    /// plugged in, and an iPhone acting as a Continuity Camera.
    private static var deviceTypes: [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .externalUnknown]
        if #available(macOS 14.0, *) {
            types = [.builtInWideAngleCamera, .external, .continuityCamera]
        }
        return types
    }

    public init(emit: @escaping @MainActor (CameraState) -> Void) {
        self.emit = emit
    }

    // MARK: - Control

    /// Whether the capture session is, or is about to be, running.
    public var isRunning: Bool { state.phase.isRunning }

    public var snapshot: CameraState { state }

    /// Opens the camera, or closes it if it is already open.
    public func toggle() {
        if state.isPresented {
            close()
        } else {
            open()
        }
    }

    /// Opens the preview, asking for permission if it has not been asked yet.
    public func open() {
        guard !state.isPresented else { return }
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            fail(.unavailable("The camera needs the NotchHub app bundle"))
            return
        }
        state.phase = .starting
        publish()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.state.phase == .starting else { return }
                    if granted {
                        self.startSession()
                    } else {
                        self.fail(.permissionDenied)
                    }
                }
            }
        default:
            fail(.permissionDenied)
        }
    }

    /// Closes the preview and releases the camera completely.
    public func close() {
        teardown()
        state = CameraState(isExpanded: state.isExpanded, isMirrored: state.isMirrored)
        publish()
    }

    /// Between the small and larger previews. The session is untouched: this is
    /// a change of frame, not of capture.
    public func toggleSize() {
        state.isExpanded.toggle()
        publish()
    }

    /// Flips the picture. Presentation only — it changes nothing that is
    /// captured, because nothing is.
    public func toggleMirror() {
        state.isMirrored.toggle()
        publish()
    }

    /// Switches to the next camera the Mac has, keeping the preview up.
    public func switchDevice() {
        guard let next = state.nextDeviceID, next != state.deviceID else { return }
        select(deviceID: next)
    }

    // MARK: - Session

    private func startSession() {
        let devices = Self.discover()
        state.devices = devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
        guard !devices.isEmpty else {
            fail(.noDevice)
            return
        }
        // Prefer the camera chosen last time, when it is still here.
        let wanted = devices.first { $0.uniqueID == state.deviceID } ?? devices[0]
        select(deviceID: wanted.uniqueID)
    }

    /// Builds (or rebuilds) the session around one device.
    private func select(deviceID: String) {
        guard let device = Self.discover().first(where: { $0.uniqueID == deviceID }) else {
            fail(.noDevice)
            return
        }
        state.deviceID = deviceID

        let session = self.session ?? AVCaptureSession()
        let previousInput = self.input
        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if let previousInput { session.removeInput(previousInput) }
            guard session.canAddInput(newInput) else {
                session.commitConfiguration()
                fail(.unavailable("This camera is in use"))
                return
            }
            session.addInput(newInput)
            session.sessionPreset = .high
            session.commitConfiguration()
            self.input = newInput
        } catch {
            fail(.unavailable("The camera could not be opened"))
            return
        }

        if self.session == nil {
            self.session = session
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            previewLayer = layer
        }

        // `startRunning` negotiates with the device and can take a moment.
        sessionQueue.async { [weak self] in
            if !session.isRunning { session.startRunning() }
            Task { @MainActor in
                guard let self, self.state.phase.isRunning else {
                    // Closed while it was starting: never leave it running.
                    session.stopRunning()
                    return
                }
                self.state.phase = .live
                self.publish()
            }
        }
    }

    /// Stops and dismantles everything. Idempotent.
    private func teardown() {
        previewLayer?.session = nil
        previewLayer = nil
        guard let session else {
            input = nil
            return
        }
        self.session = nil
        let closing = input
        input = nil
        // Off the main thread, because `stopRunning` blocks until the device
        // has actually let go — which is the point.
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            if let closing { session.removeInput(closing) }
            session.commitConfiguration()
        }
    }

    private func fail(_ failure: CameraFailure) {
        teardown()
        state.phase = .failed(failure)
        publish()
    }

    private static func discover() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private func publish() {
        emit(state)
    }
}
