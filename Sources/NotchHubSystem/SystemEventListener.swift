import AppKit
import Foundation
import Network

/// Observes system lifecycle and connectivity.
///
/// Uses `NSWorkspace` for sleep/wake and `NWPathMonitor` for the network — both
/// public, native APIs. Emits only on transitions, never on steady state.
public final class SystemEventListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private var lastPathSatisfied: Bool?

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    public func start() {
        guard workspaceObservers.isEmpty, pathMonitor == nil else { return }
        let center = NSWorkspace.shared.notificationCenter

        let wake = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.emit(SystemEvent(source: .system, payload: .didWake))
        }
        let sleep = center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.emit(SystemEvent(source: .system, payload: .willSleep))
        }
        workspaceObservers = [wake, sleep]

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handlePath(path)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.notchhub.network"))
        pathMonitor = monitor
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func handlePath(_ path: NWPath) {
        let satisfied = path.status == .satisfied
        guard satisfied != lastPathSatisfied else { return }
        lastPathSatisfied = satisfied

        let name: String
        if !satisfied {
            name = "Disconnected"
        } else if path.usesInterfaceType(.wifi) {
            name = "Wi-Fi"
        } else if path.usesInterfaceType(.wiredEthernet) {
            name = "Ethernet"
        } else if path.usesInterfaceType(.cellular) {
            name = "Cellular"
        } else {
            name = "Connected"
        }
        emit(SystemEvent(source: .network, payload: .network(name: name)))
    }
}
