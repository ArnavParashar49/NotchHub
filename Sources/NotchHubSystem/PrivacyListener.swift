import AppKit
import NotchHubCore

/// Reports whether the camera and microphone are in use.
///
/// The mic is easy and reliable: CoreAudio exposes exactly which processes are
/// running input. The camera has no equivalent public API, so it is reported
/// only when a known capture app is frontmost — an honest approximation rather
/// than a fabricated "recording" light.
final class PrivacyListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var timer: Timer?
    private var lastCamera = false
    private var lastMicrophone = false

    /// Apps that signal camera use by being frontmost.
    private static let cameraApps: Set<String> = [
        "com.apple.FaceTime",
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.apple.PhotoBooth",
        "com.apple.QuickTimePlayerX",
    ]

    init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    var name: String { "Privacy" }

    func start() {
        stop()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let microphone = AudioInput.isInUse()
        let camera = Self.isCameraLikelyInUse()

        if camera || microphone {
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
            NotchLog.debug("privacy: camera=\(camera) mic=\(microphone) app=\(bundleID)")
        }

        guard microphone != lastMicrophone || camera != lastCamera else { return }
        lastMicrophone = microphone
        lastCamera = camera
        emit(SystemEvent(source: .privacy, payload: .privacy(camera: camera, microphone: microphone)))
    }

    /// Whether the camera is probably in use: a capture-capable app is frontmost.
    private static func isCameraLikelyInUse() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return cameraApps.contains(bundleID)
    }
}
