import CoreGraphics
import Foundation

/// NEO's presence in the notch: its held state, whether its core is there,
/// and the moment it settles after a turn.
///
/// The pet IS NEO (`PetBrain`, `PetMood.neo`): while NEO is listening,
/// thinking, speaking or asking, the pet's pose says so, and the island's
/// shape never changes for it — nothing grows, nothing is added. This model
/// is pure and clock-driven, like the panel's: every method takes `now`,
/// and `nextWake(at:)` says when something will change on its own (a held
/// state becoming due, the settle after idle), so the app runs no timers.
public struct NeoPresenceModel: Equatable, Sendable {
    /// How long after NEO returns to idle it still counts as active — a
    /// click on the island in that moment still opens its chat — before
    /// the pet settles back into its own life.
    public static let settleDelay: TimeInterval = 1.2

    public private(set) var hold: NeoStateHold
    /// Whether the core's socket is up. While it is not, NEO may simply be off.
    public private(set) var isConnected = false
    /// When the held state became idle after being busy; `nil` while busy.
    private var idleAt: Date?
    private var lastReported: (state: NeoState, active: Bool)?

    public init(minDwell: TimeInterval = NeoStateHold.defaultMinDwell) {
        hold = NeoStateHold(minDwell: minDwell)
    }

    public static func == (lhs: NeoPresenceModel, rhs: NeoPresenceModel) -> Bool {
        lhs.hold == rhs.hold && lhs.isConnected == rhs.isConnected && lhs.idleAt == rhs.idleAt
    }

    /// The state NEO shows (after the dwell), or `.idle` while it is away.
    public var state: NeoState { isConnected ? hold.current : .idle }

    /// Takes one fact from the core. Returns when to come back with
    /// `tick(at:)`, if something will change on its own. Cards, transcripts,
    /// notes and wakes are the panel's business, not the pet's.
    @discardableResult
    public mutating func receive(_ fact: NeoFact, at now: Date) -> Date? {
        switch fact {
        case let .connected(up):
            isConnected = up
            if !up {
                hold.receive(.idle, at: now)
                hold.settle(at: now)
                idleAt = nil
            }
        case let .state(next):
            let wasIdle = hold.current == .idle
            hold.receive(next, at: now)
            noteIdle(wasIdle: wasIdle, at: now)
        case .transcript, .note, .error, .card, .woke:
            break
        }
        lastReported = (state, isActive(at: now))
        return nextWake(at: now)
    }

    /// Advances the clock: applies a held state whose dwell has ended.
    /// Returns whether what NEO shows has changed since the app last heard.
    @discardableResult
    public mutating func tick(at now: Date) -> Bool {
        let wasIdle = hold.current == .idle
        if hold.settle(at: now) { noteIdle(wasIdle: wasIdle, at: now) }
        let current = (state, isActive(at: now))
        defer { lastReported = current }
        guard let last = lastReported else { return false }
        return current.0 != last.state || current.1 != last.active
    }

    private mutating func noteIdle(wasIdle: Bool, at now: Date) {
        if hold.current == .idle {
            if !wasIdle { idleAt = now }
        } else {
            idleAt = nil
        }
    }

    /// The next moment NEO's presence changes on its own: a held state
    /// becoming due, or the settle after idle.
    public func nextWake(at now: Date) -> Date? {
        var dates: [Date] = []
        if let pending = hold.pending { dates.append(pending.due) }
        if hold.current == .idle, hold.pending == nil, let settle = settleDate, settle > now { dates.append(settle) }
        return dates.min()
    }

    private var settleDate: Date? { idleAt?.addingTimeInterval(Self.settleDelay) }

    /// Whether NEO is active: doing anything, or within `settleDelay` of
    /// having stopped.
    public func isActive(at now: Date) -> Bool {
        guard isConnected else { return false }
        if hold.current != .idle { return true }
        if let pending = hold.pending, pending.state != .idle { return true }
        guard let settle = settleDate else { return false }
        return now < settle
    }
}

/// What a click on the island does for NEO.
///
/// While NEO is active — the pet is NEO, and it is busy — the island IS
/// NEO's door: a click anywhere on it (the pet included) opens the chat.
/// With NEO idle, clicks keep the island's own meaning (the dashboard, the
/// song, the call controls, the pet's own panel). With NEO's panel open the
/// panel is the page's. Another surface (settings, the Tray, the pet's
/// panel) keeps its controls.
public enum NeoIslandClick {
    public enum Outcome: Equatable, Sendable {
        case open
        case none
    }

    public static func outcome(neoActive: Bool, panelOpen: Bool, otherPanel: Bool) -> Outcome {
        guard neoActive, !panelOpen, !otherPanel else { return .none }
        return .open
    }
}
