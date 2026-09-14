import Foundation

/// The island's activity model: one primary activity plus a stack behind it.
///
/// Ordering is by priority (descending), then by recency (newest first), so a
/// fresh event of equal priority takes the island immediately.
public final class ActivityQueue {
    private var items: [Activity] = []

    /// The id of an activity temporarily focused on the island regardless of
    /// priority (e.g. a volume change while music is playing). `nil` when no
    /// transient is focused.
    private var transientID: UUID?

    public init() {}

    /// Every tracked activity, ordered as the island would present them.
    public var all: [Activity] { ordered() }

    /// The activity currently occupying the island, if any.
    ///
    /// A temporarily-focused transient wins over the highest-priority
    /// persistent activity; otherwise the highest priority wins.
    public var current: Activity? {
        if let id = transientID, let transient = items.first(where: { $0.id == id }) {
            return transient
        }
        return ordered().first
    }

    /// How many activities are waiting behind the primary one (the "+N" badge).
    public var stackCount: Int { max(0, ordered().count - 1) }

    public var isEmpty: Bool { ordered().isEmpty }

    /// Adds an activity. A newer activity of the same kind replaces the older
    /// one rather than stacking — volume changes should not pile up.
    @discardableResult
    public func push(_ activity: Activity) -> Activity {
        items.removeAll { $0.kind == activity.kind && $0.kind.isReplaceable }
        items.append(activity)
        return activity
    }

    /// Updates the matching in-flight activity in place, or pushes `activity`
    /// when there is none.
    ///
    /// An activity matches on kind AND title, so two concurrent downloads stay
    /// separate while each one's progress updates its own row. The existing id
    /// is kept: the island keys its SwiftUI content on the id, and a fresh id
    /// on every tick would make the surface thrash as if it were brand new.
    @discardableResult
    public func upsert(_ activity: Activity) -> Activity {
        guard let index = items.firstIndex(where: { $0.kind == activity.kind && $0.title == activity.title }) else {
            return push(activity)
        }
        let updated = activity.withID(items[index].id)
        items[index] = updated
        return updated
    }

    /// Removes a specific activity.
    public func remove(id: UUID) {
        if transientID == id { transientID = nil }
        items.removeAll { $0.id == id }
    }

    /// Replaces an activity with a new version of itself.
    public func replace(_ id: UUID, with activity: Activity) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = activity
        }
    }

    /// Takes the island immediately with `activity`, regardless of priority,
    /// marking it temporary. When its `autoDismiss` elapses (driven via
    /// `tick(now:)`), the queue drops it and returns to the highest-priority
    /// persistent activity. This is how a volume change surfaces over playing
    /// music and then hands the island back.
    ///
    /// A repeat of a transient already on the island (holding a brightness or
    /// volume key) keeps that surface's id and restarts its lifetime, so the
    /// readout updates in place instead of re-animating as a new surface on
    /// every step.
    public func focusTemporarily(_ activity: Activity) {
        var activity = activity
        if activity.kind.isReplaceable, let existing = items.first(where: { $0.kind == activity.kind }) {
            activity = activity.withID(existing.id)
        }
        push(activity)
        transientID = activity.id
    }

    /// Drops any temporarily-focused activity and returns the island to the
    /// highest-priority persistent activity.
    public func resumePersistent() {
        if let id = transientID {
            remove(id: id)
            transientID = nil
        }
    }

    /// Removes every activity of a kind.
    public func remove(kind: ActivityKind) {
        if let id = transientID, items.contains(where: { $0.id == id && $0.kind == kind }) {
            transientID = nil
        }
        items.removeAll { $0.kind == kind }
    }

    /// Clears the island entirely.
    public func removeAll() {
        transientID = nil
        items.removeAll()
    }

    /// Drops expired activities. Returns the ones that were dismissed.
    @discardableResult
    public func tick(now: Date = Date()) -> [Activity] {
        // A focused transient hands the island back once its lifetime elapses.
        if let id = transientID, let transient = items.first(where: { $0.id == id }),
           transient.isExpired(at: now) {
            resumePersistent()
        }
        let expired = items.filter { $0.isExpired(at: now) }
        if !expired.isEmpty {
            let ids = Set(expired.map(\.id))
            items.removeAll { ids.contains($0.id) }
        }
        return expired
    }

    /// Updates an in-flight activity (progress, elapsed) without re-pushing it.
    public func update(id: UUID, progress: Double? = nil, elapsed: TimeInterval? = nil, subtitle: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let progress { items[index].progress = progress }
        if let elapsed { items[index].elapsed = elapsed }
        if let subtitle { items[index].subtitle = subtitle }
    }

    private func ordered() -> [Activity] {
        items.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

private extension ActivityKind {
    /// Kinds where a newer event supersedes the previous one.
    var isReplaceable: Bool {
        switch self {
        case .volume, .brightness, .battery, .lowBattery, .wifi, .bluetooth, .airpods, .clipboard, .music, .meeting, .dictation, .skin, .codingAgent:
            return true
        // A timer ticks several times a second; each tick is an UPDATE of the
        // same stopwatch, not a new activity. Without this the queue would
        // accumulate one item per tick and never drain.
        case .timer:
            return true
        default:
            return false
        }
    }
}
