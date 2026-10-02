import Foundation
import NotchHubCore

/// A native observer of one part of the system.
///
/// Listeners are deliberately dumb: they observe, they emit, they stop. They
/// hold no activity state and know nothing about the UI. This is the boundary
/// that keeps system integration out of the presentation layer.
public protocol SystemListener: AnyObject {
    /// Stable identifier, used in logs and diagnostics.
    var name: String { get }
    /// Begin observing. Must be idempotent.
    func start()
    /// Stop observing and release any OS resources. Must be idempotent.
    func stop()
}

public extension SystemListener {
    var name: String { String(describing: type(of: self)) }
}

/// Fans events out from listeners to interested subscribers on the main queue.
///
/// Deliberately tiny: no buffering, no replay. The app subscribes once and
/// translates events into activities.
public final class SystemEventBus {

    private var handlers: [(SystemEvent) -> Void] = []
    private let lock = NSLock()

    public init() {}

    /// Registers a handler. Handlers are always invoked on the main queue.
    public func subscribe(_ handler: @escaping (SystemEvent) -> Void) {
        lock.lock()
        handlers.append(handler)
        lock.unlock()
    }

    /// Publishes an event to every subscriber.
    public func publish(_ event: SystemEvent) {
        lock.lock()
        let current = handlers
        lock.unlock()
        DispatchQueue.main.async {
            current.forEach { $0(event) }
        }
    }
}

/// Owns every listener and pumps their events onto the bus.
///
/// This is the single place that knows the full set of system integrations.
/// Listeners are described by `ListenerSpec`s keyed by an id that includes
/// their configuration, so a settings change can start and stop ONLY the
/// listeners it affects (`update(settings:)`) instead of rebuilding them all.
public final class SystemMonitor {

    public let bus = SystemEventBus()
    private var entries: [(id: String, listener: SystemListener)] = []
    private var isRunning = false

    public init() {}

    /// What a settings update did.
    public struct Changes: Equatable {
        public var added: Int
        public var removed: Int
    }

    /// One listener the monitor may run: its identity (feature + configuration)
    /// and how to build it.
    struct ListenerSpec {
        let id: String
        let make: (@escaping (SystemEvent) -> Void) -> SystemListener
    }

    /// Registers a listener. Register before `start()`.
    public func register(_ listener: SystemListener) {
        entries.append(("custom:\(ObjectIdentifier(listener).hashValue)", listener))
        if isRunning { listener.start() }
    }

    /// Builds the default set of listeners for this platform. A disabled
    /// feature creates no listener and no background work.
    public static func defaultMonitor(settings: FeatureSettings = FeatureSettings()) -> SystemMonitor {
        let monitor = SystemMonitor()
        monitor.update(settings: settings)
        return monitor
    }

    /// The listeners a feature set calls for, in start order.
    static func specs(for settings: FeatureSettings) -> [ListenerSpec] {
        let enabled = settings.isEnabled
        var specs: [ListenerSpec] = [
            // Core system lifecycle — always on.
            ListenerSpec(id: "system") { SystemEventListener(emit: $0) },
        ]
        func add(_ feature: Feature, _ id: String, _ make: @escaping (@escaping (SystemEvent) -> Void) -> SystemListener) {
            if enabled(feature) { specs.append(ListenerSpec(id: id, make: make)) }
        }
        add(.battery, "battery") { BatteryListener(emit: $0) }
        add(.volume, "volume") { VolumeListener(emit: $0) }
        add(.brightness, "brightness") { BrightnessListener(emit: $0) }
        add(.music, "music") { NowPlayingListener(emit: $0) }
        add(.downloads, "downloads") { DownloadListener(emit: $0) }
        add(.clipboard, "clipboard") { ClipboardTrayListener(emit: $0) }
        add(.meetings, "meetings") { MeetingListener(emit: $0) }
        add(.privacy, "privacy") { PrivacyListener(emit: $0) }
        if enabled(.bluetooth) || enabled(.airpods) {
            // One listener serves both toggles; the bridge decides the surface.
            specs.append(ListenerSpec(id: "bluetooth") { BluetoothListener(emit: $0) })
        }
        add(.calendar, "calendar") { CalendarListener(emit: $0) }
        add(.weather, "weather") { WeatherListener(emit: $0) }
        add(.notifications, "notifications") { NotificationListener(emit: $0) }
        add(.focus, "focus") { FocusListener(emit: $0) }
        add(.codingAgent, "codingAgent") { CodingAgentListener(emit: $0) }
        if enabled(.neo) {
            // With NEO's page installed NotchHub hosts NEO's whole UI, and
            // says so to the core; without it, the lane alone.
            let hostsUI = NeoUIBundle.installedFolder() != nil
            specs.append(ListenerSpec(id: hostsUI ? "neo+ui" : "neo") { NeoListener(hostsUI: hostsUI, emit: $0) })
        }
        if enabled(.appDetails) {
            // Its configuration is part of its identity: toggling Coding Agent
            // rebuilds it with or without session tracking.
            let includeAgents = enabled(.codingAgent)
            specs.append(ListenerSpec(id: includeAgents ? "appDetails+agents" : "appDetails") {
                AppContextListener(includeAgents: includeAgents, emit: $0)
            })
        }
        // Wi-Fi and the frontmost app have no toggle of their own.
        specs.append(ListenerSpec(id: "wifi") { DeviceListener(emit: $0) })
        specs.append(ListenerSpec(id: "frontmostApp") { FrontmostAppListener(emit: $0) })
        return specs
    }

    /// Brings the listeners in line with `settings`: stops and drops the ones
    /// no longer called for, builds (and, while running, starts) the new ones,
    /// and leaves every other listener untouched.
    @discardableResult
    public func update(settings: FeatureSettings) -> Changes {
        let desired = Self.specs(for: settings)
        let desiredIDs = Set(desired.map(\.id))

        var removed = 0
        entries.removeAll { entry in
            guard !entry.id.hasPrefix("custom:"), !desiredIDs.contains(entry.id) else { return false }
            if isRunning { entry.listener.stop() }
            removed += 1
            return true
        }

        let existing = Set(entries.map(\.id))
        var added = 0
        for spec in desired where !existing.contains(spec.id) {
            let listener = spec.make { [weak self] in self?.bus.publish($0) }
            entries.append((spec.id, listener))
            if isRunning { listener.start() }
            added += 1
        }

        // Keep start order stable for logs and diagnostics.
        let order = Dictionary(uniqueKeysWithValues: desired.enumerated().map { ($1.id, $0) })
        entries.sort { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
        return Changes(added: added, removed: removed)
    }

    /// Starts every registered listener.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        NotchLog.debug("monitor: starting \(entries.count) listeners")
        entries.forEach {
            NotchLog.debug("monitor: starting \($0.listener.name)")
            $0.listener.start()
        }
    }

    /// Stops every registered listener.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        entries.forEach { $0.listener.stop() }
    }

    /// Restarts only the matching listeners, leaving the rest running — e.g.
    /// the weather listener after its city changes.
    public func restart(where predicate: (SystemListener) -> Bool) {
        guard isRunning else { return }
        for entry in entries where predicate(entry.listener) {
            entry.listener.stop()
            entry.listener.start()
        }
    }

    /// Asks the app-context listener to read again soon (after the island
    /// drove the browser, so the strip and panel catch up at once).
    public func refreshAppContext() {
        entries.compactMap { $0.listener as? AppContextListener }.forEach { $0.refreshSoon() }
    }

    /// The island left a call: the meeting listener forgets it at once.
    public func meetingLeft(_ meeting: Meeting) {
        entries.compactMap { $0.listener as? MeetingListener }.forEach { $0.noteLeft(meeting) }
    }

    /// Asks NEO.app, through the NEO listener, for one of its menu's actions
    /// (the NEO section of Settings). Nothing happens while NEO is off or away.
    public func neoShell(_ action: NeoShellAction) {
        entries.compactMap { $0.listener as? NeoListener }.forEach { $0.send(action) }
    }

    /// Asks the meeting listener to read the call's state again soon.
    public func refreshMeeting() {
        entries.compactMap { $0.listener as? MeetingListener }.forEach { $0.pollSoon() }
    }

    public var listenerNames: [String] { entries.map(\.listener.name) }
}
