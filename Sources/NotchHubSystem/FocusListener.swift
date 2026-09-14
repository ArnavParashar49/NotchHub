import AppKit
import NotchHubCore

/// Observes the system's Focus / Do Not Disturb state.
///
/// On macOS 12+ the old `com.apple.notificationcenterui doNotDisturb` default is
/// gone. The live state now lives in the Focus assertion store at
/// `~/Library/DoNotDisturb/DB/Assertions.json`, where an *active* Focus mode
/// appears as an assertion record and a disabled one as an invalidation record.
///
/// The listener is deliberately defensive: the file's inner shape is private to
/// Apple, so it looks for any active assertion (a record that is not an
/// invalidation) and reads its mode identifier without assuming an exact key
/// name. If the file is missing or unreadable — including when Full Disk Access
/// has not been granted — the listener simply reports nothing rather than
/// guessing, honouring the spec's "never fake unavailable information" rule.
public final class FocusListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private var timer: Timer?
    private var lastActive: Bool?

    /// Focus changes are user-driven and slow; a few seconds of latency is
    /// invisible and keeps the poll cheap.
    private let pollInterval: TimeInterval

    public init(pollInterval: TimeInterval = 4, emit: @escaping (SystemEvent) -> Void) {
        self.pollInterval = pollInterval
        self.emit = emit
    }

    public var name: String { "Focus" }

    public func start() {
        stop()
        // Seed from the current state so we only emit on a real transition.
        lastActive = Self.currentMode() != nil
        assertStoreReadable()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Logs whether the assertion store is actually readable. A silent TCC block
    /// is otherwise indistinguishable from "no Focus engaged", which would make
    /// the feature look broken with no clue why.
    private func assertStoreReadable() {
        guard CommandLine.arguments.contains("--verbose") else { return }
        if Self.assertionStoreData() != nil {
            NotchLog.debug("focus: assertion store readable")
        } else {
            NotchLog.debug("focus: assertion store UNREADABLE (Full Disk Access needed)")
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let mode = Self.currentMode()
        let active = mode != nil
        guard active != lastActive else { return }
        lastActive = active
        emit(SystemEvent(source: .focus, payload: .focus(active: active, name: mode)))
    }

    // MARK: - Assertion store

    /// The name of the active Focus mode, or nil when no Focus is engaged.
    static func currentMode() -> String? {
        guard let data = assertionStoreData() else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["data"] as? [[String: Any]] else { return nil }

        for record in records {
            // An *active* assertion lives under a key that mentions assertions
            // but is not an invalidation record. Matching loosely keeps this
            // working across macOS revisions that rename the key.
            for (key, value) in record {
                let lower = key.lowercased()
                // An *active* assertion lives under a records key that is
                // neither an invalidation nor a request. Matching loosely keeps
                // this working across macOS revisions that rename the key.
                let isCandidate = (lower.contains("assertion") || lower.contains("records"))
                    && !lower.contains("invalidation")
                    && !lower.contains("request")
                guard isCandidate, let assertions = value as? [[String: Any]] else { continue }
                if let name = assertions.compactMap(activeAssertionMode).first {
                    return name
                }
            }
        }
        return nil
    }

    /// Reads a human mode name from an active assertion record.
    private static func activeAssertionMode(_ assertion: [String: Any]) -> String? {
        guard let details = assertion["assertionDetails"] as? [String: Any] else { return nil }
        // Prefer the friendly name when present, else derive from the identifier.
        if let name = details["assertionDetailsModeName"] as? String, !name.isEmpty {
            return name
        }
        if let identifier = details["assertionDetailsModeIdentifier"] as? String, !identifier.isEmpty {
            return friendlyName(for: identifier)
        }
        return "Focus"
    }

    /// Turns `com.apple.donotdisturb.mode.work` into `Work`.
    private static func friendlyName(for identifier: String) -> String {
        guard let last = identifier.split(separator: ".").last else { return "Focus" }
        let name = last.replacingOccurrences(of: "-", with: " ")
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static func assertionStoreData() -> Data? {
        let path = ("~/Library/DoNotDisturb/DB/Assertions.json" as NSString).expandingTildeInPath
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }
}
