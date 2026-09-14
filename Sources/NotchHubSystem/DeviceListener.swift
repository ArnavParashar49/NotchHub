import AppKit
import CoreWLAN
import NotchHubCore

/// Reports Do Not Disturb and Wi-Fi changes.
///
/// Both are cheap, low-frequency facts: the island shows them for a moment and
/// then gets out of the way.
final class DeviceListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var lastSSID: String?

    init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    var name: String { "Device" }

    func start() {
        stop()

        // Wi-Fi: CoreWLAN posts when the interface joins or leaves.
        let wifiCenter = NSWorkspace.shared.notificationCenter
        let token = wifiCenter.addObserver(
            forName: NSNotification.Name("com.apple.wifi.services-created"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pollWiFi()
        }
        observers.append(token)

        // Wi-Fi is polled on the same cadence. Focus has its own listener
        // (`FocusListener`), which reads the modern assertion store.
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollWiFi()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        pollWiFi()
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Wi-Fi

    private func pollWiFi() {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else { return }
        let ssid = interface.ssid()
        let connected = interface.powerOn() && ssid != nil
        guard ssid != lastSSID else { return }
        lastSSID = ssid
        emit(SystemEvent(source: .wifi, payload: .wifi(ssid: ssid, connected: connected)))
    }

    // MARK: - Focus / Do Not Disturb
    //
    // Focus is owned by `FocusListener`, which reads the modern assertion store
    // rather than the `doNotDisturb` default removed in macOS 12+.
}
