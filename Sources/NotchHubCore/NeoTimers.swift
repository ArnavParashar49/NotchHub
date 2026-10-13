import Foundation

/// NEO's timers in the notch: a countdown on the island while one runs.
///
/// "Set a pasta timer for 4 minutes" is NEO's: its core keeps the timer, says
/// it out loud when it goes off and is the only one that can cancel it. The
/// island only shows it. The core tells its clients about its timers on the
/// local, token-authenticated socket — the hello lists the ones counting
/// down (`timers`), and `activity` events say when one starts and when one
/// is over — and the listener turns that into `NeoFact`s. Here they become
/// three plain things:
/// - `NeoTimerInfo`: one timer, as the core announced it;
/// - `NeoTimers`: every timer NEO has running right now, and how the island
///   words the soonest one (`NeoTimerLine`: "Pasta 4:12");
/// - `NeoTimerSurface`: what that puts in the activity queue — one countdown
///   (the soonest), and a short "Pasta · done" when one goes off.
///
/// Nothing is sent per second: the time left is worked out here, from the
/// end the core gave (`ends_at`) and the Mac's own clock. Nothing goes back
/// to the core either (cancelling is NEO's, by voice or chat), and nothing is
/// written anywhere: the timers live in memory while the core is connected,
/// and go when it does.

/// One of NEO's timers, as its core announced it.
public struct NeoTimerInfo: Equatable, Sendable {
    /// `timer:` and 12 hex characters: the same in the hello and in events,
    /// and across the core's restarts.
    public let id: String
    /// One plain line of at most 40 characters, "Timer" when it has no name.
    /// The user's (or a model's) words: shown as text and nothing else.
    public let title: String
    /// When it goes off, on the Mac's own clock.
    public let endsAt: Date

    public init(id: String, title: String, endsAt: Date) {
        self.id = id
        self.title = title
        self.endsAt = endsAt
    }

    /// The longest title the core sends, and so the longest kept.
    public static let titleLimit = 40
    /// An id longer than this is not one of NEO's.
    static let idLimit = 64

    /// From the core's JSON object: a hello's entry, or an `activity` event's
    /// data. `nil` without a usable id or end (`ends_at`, a real number of
    /// seconds since 1970 — not a boolean, not text, not infinite).
    public init?(payload: [String: Any]) {
        guard let id = Self.id(payload["id"]),
              let seconds = payload["ends_at"] as? NSNumber,
              CFGetTypeID(seconds) != CFBooleanGetTypeID(),
              seconds.doubleValue.isFinite else { return nil }
        self.init(id: id, title: Self.title(payload["title"]), endsAt: Date(timeIntervalSince1970: seconds.doubleValue))
    }

    /// The id a timer is known by, or `nil` when there is none worth keeping.
    public static func id(_ value: Any?) -> String? {
        guard let id = value as? String, !id.isEmpty, id.count <= idLimit else { return nil }
        return id
    }

    /// The core's title made safe to show: one line (line breaks and other
    /// control characters become spaces, runs of spaces one), no bidi
    /// controls that could turn the line around, at most `titleLimit`
    /// characters — "Timer" when nothing is left.
    public static func title(_ value: Any?) -> String {
        guard let raw = value as? String else { return "Timer" }
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if bidiControls.contains(scalar.value) { continue }
            let category = scalar.properties.generalCategory
            let breaksLine = category == .control || category == .lineSeparator || category == .paragraphSeparator
            scalars.append(breaksLine ? " " : scalar)
        }
        let line = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let capped = String(line.prefix(titleLimit)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? "Timer" : capped
    }

    /// LRE, RLE, PDF, LRO, RLO, LRI, RLI, FSI, PDI, LRM, RLM, ALM.
    private static let bidiControls: Set<UInt32> = [
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x200E, 0x200F, 0x061C,
    ]
}

/// What the island's bar says for NEO's timers: a name, and beside it the
/// time left ("Pasta" "4:12") or that it went off ("Pasta" "· done"). Two
/// parts because they are drawn as two: the name may be cut short, the
/// clock never is, and it is drawn in tabular digits.
public struct NeoTimerLine: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    /// The line as one string: "Pasta 4:12".
    public var text: String { "\(name) \(value)" }
}

/// Every timer NEO has running, as its core last said, and how the island
/// words them. Pure: it holds no clock of its own — every question takes
/// `now`.
public struct NeoTimers: Equatable, Sendable {

    /// What one fact did to NEO's timers.
    public enum Change: Equatable, Sendable {
        /// Nothing: not about timers, or what the island knew already.
        case none
        /// A timer started, came back, was cancelled — or the core went away.
        case changed
        /// A timer went off; its name, for the "done" moment.
        case wentOff(title: String)
    }

    /// The most timers kept at once. NEO's own core never comes near it;
    /// it bounds what a confused one could make the island hold.
    public static let maxTimers = 64
    /// The longest name the island's line keeps; past it the name is cut
    /// (with "…") so the clock beside it always shows.
    public static let labelLimit = 16
    /// The longest countdown shown, "99:59:59": nothing the core says can
    /// overflow the clock.
    public static let longestCountdown: TimeInterval = 100 * 3600 - 1

    /// The timers counting down, by id.
    public private(set) var running: [String: NeoTimerInfo] = [:]

    public init() {}

    public var isEmpty: Bool { running.isEmpty }

    /// Takes one fact from NEO's core.
    /// - the hello's list replaces every timer (what it does not name is gone);
    /// - a started one is kept by its id (again and again, on a restore);
    /// - an ended one is dropped, and reported as gone off when it did;
    /// - the core going away takes them all.
    @discardableResult
    public mutating func receive(_ fact: NeoFact) -> Change {
        switch fact {
        case let .neoTimers(list):
            var next: [String: NeoTimerInfo] = [:]
            for timer in list where next.count < Self.maxTimers || next[timer.id] != nil {
                next[timer.id] = timer
            }
            guard next != running else { return .none }
            running = next
            return .changed
        case let .neoTimer(timer):
            guard running[timer.id] != timer else { return .none }
            guard running[timer.id] != nil || running.count < Self.maxTimers else { return .none }
            running[timer.id] = timer
            return .changed
        case let .neoTimerEnd(id, title, done):
            let known = running.removeValue(forKey: id)
            if done { return .wentOff(title: known?.title ?? title) }
            return known == nil ? .none : .changed
        case .connected(false):
            guard !running.isEmpty else { return .none }
            running = [:]
            return .changed
        default:
            return .none
        }
    }

    /// The timer that goes off first (the lower id on a tie, so the choice
    /// never wavers between two that end together).
    public var soonest: NeoTimerInfo? {
        running.values.min { lhs, rhs in
            lhs.endsAt != rhs.endsAt ? lhs.endsAt < rhs.endsAt : lhs.id < rhs.id
        }
    }

    /// The island's line for the soonest timer at `now`, or `nil` when NEO
    /// has none.
    public func countdownLine(at now: Date) -> NeoTimerLine? {
        soonest.map { Self.countdownLine($0, at: now) }
    }

    /// The same, as one string ("Pasta 4:12").
    public func countdown(at now: Date) -> String? {
        countdownLine(at: now)?.text
    }

    // MARK: - Words

    /// "Pasta" "4:12": the timer's name, then the time left.
    public static func countdownLine(_ timer: NeoTimerInfo, at now: Date) -> NeoTimerLine {
        NeoTimerLine(name: label(timer.title), value: clock(secondsLeft(until: timer.endsAt, at: now)))
    }

    /// "Pasta" "· done": the moment it went off.
    public static func doneLine(_ title: String) -> NeoTimerLine {
        NeoTimerLine(name: label(title), value: "· done")
    }

    /// "Pasta 4:12", as one string.
    public static func countdownTitle(_ timer: NeoTimerInfo, at now: Date) -> String {
        countdownLine(timer, at: now).text
    }

    /// "Pasta · done", as one string.
    public static func doneTitle(_ title: String) -> String {
        doneLine(title).text
    }

    /// Whole seconds left until `endsAt`, rounded up — a 5-minute timer opens
    /// on 5:00 and shows 0:01 through its last second — and never below 0
    /// (a timer restored late, after the Mac slept, shows 0:00 until the core
    /// says it went off).
    public static func secondsLeft(until endsAt: Date, at now: Date) -> Int {
        let left = endsAt.timeIntervalSince(now)
        guard left.isFinite, left > 0 else {
            return left == .infinity ? Int(longestCountdown) : 0
        }
        return Int(min(left, longestCountdown).rounded(.up))
    }

    /// `m:ss` under an hour, `h:mm:ss` past it.
    public static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// The name as the island's line shows it: "Timer" for none, and at most
    /// `labelLimit` characters, cut with "…" (at a word's end when the cut
    /// falls on a space).
    public static func label(_ title: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Timer" }
        guard name.count > labelLimit else { return name }
        let kept = String(name.prefix(labelLimit - 1)).trimmingCharacters(in: .whitespaces)
        return kept + "…"
    }
}

/// NEO's timers on the island: at most one countdown — the soonest timer —
/// and a short "done" moment when one goes off.
///
/// Both are activities of NEO's own kind (`.neoTimer`) — the name as their
/// title, the clock (or "· done") as their subtitle — so they never meet
/// NotchHub's focus timer (`.timer`) in the queue's same-kind replacement.
/// - The countdown is persistent, at NotchHub's timer priority (70), and
///   keeps one identity and one birth date for as long as any timer runs:
///   its title is replaced in place as the seconds go, so the island never
///   sees a new surface, and its place among equals never changes — beside
///   a running focus timer the two never take turns.
/// - "Pasta · done" is news, shown the way NotchHub shows news (a download
///   finished, an agent done): it takes the island for `doneFlash` seconds,
///   whatever else is up, and hands it back.
///
/// Nothing shows while `shows` is false — "Show NEO's timers" off, or NEO
/// not there — and switching it off takes them away at once. Everything it
/// does is to its own two activities; the rest of the queue is untouched.
public struct NeoTimerSurface: Equatable {
    /// How long "Pasta · done" holds the island.
    public static let doneFlash: TimeInterval = 5
    /// NotchHub's own timer priority (`ActivityKind.timer`).
    public static let priority = ActivityKind.neoTimer.basePriority
    public static let countdownSymbol = "timer"
    public static let doneSymbol = "checkmark.circle.fill"

    /// The countdown's activity, while one is in the queue.
    public private(set) var countdownID: UUID?
    /// When the countdown first showed: kept across every replace.
    private var since: Date?
    /// The "done" moment's activity, until the queue lets it go.
    public private(set) var doneID: UUID?
    /// The user sent the island back to idle by hand: no countdown until
    /// NEO's timers change.
    public private(set) var dismissed = false

    public init() {}

    /// A fact's change, applied: the island in line with NEO's timers, and a
    /// "done" moment for one that went off. Returns whether the queue changed
    /// in a way the island must draw. A fact that changed nothing about the
    /// timers (most of what NEO says: its state, transcripts, camera frames)
    /// changes nothing here either — the ticker keeps the seconds current.
    @discardableResult
    public mutating func apply(
        _ change: NeoTimers.Change, timers: NeoTimers, shows: Bool, in queue: ActivityQueue, at now: Date
    ) -> Bool {
        var flashed = false
        switch change {
        case .none:
            return false
        case .changed:
            dismissed = false
        case let .wentOff(title):
            dismissed = false
            flashed = wentOff(title, shows: shows, in: queue, at: now)
        }
        return sync(timers, shows: shows, in: queue, at: now) || flashed
    }

    /// Brings the countdown in line with NEO's timers at `now` (the app does
    /// this on every tick). Returns whether the queue changed in a way the
    /// island must draw: the countdown came or went, or the one showing
    /// ticked over to another second.
    @discardableResult
    public mutating func sync(_ timers: NeoTimers, shows: Bool, in queue: ActivityQueue, at now: Date) -> Bool {
        var changed = false
        if let id = doneID {
            if !queue.all.contains(where: { $0.id == id }) {
                doneID = nil // its moment is over: the queue let it go
            } else if !shows {
                queue.remove(id: id)
                doneID = nil
                changed = true
            }
        }
        let existing = countdownID.flatMap { id in queue.all.first { $0.id == id } }
        guard shows, !dismissed, let line = timers.countdownLine(at: now) else {
            if let id = countdownID {
                queue.remove(id: id)
                changed = changed || existing != nil
            }
            countdownID = nil
            since = nil
            return changed
        }
        let activity = Activity(
            id: countdownID ?? UUID(), kind: .neoTimer, title: line.name, subtitle: line.value,
            symbol: Self.countdownSymbol, priority: Self.priority, autoDismiss: 0, createdAt: since ?? now
        )
        countdownID = activity.id
        since = activity.createdAt
        if let existing {
            guard existing != activity else { return changed }
            queue.replace(activity.id, with: activity)
            return changed || queue.current?.id == activity.id
        }
        queue.push(activity)
        return true
    }

    /// The user sent the island back to idle (the queue was emptied): the
    /// countdown stays away until NEO's timers change.
    public mutating func dismiss() {
        countdownID = nil
        since = nil
        doneID = nil
        dismissed = true
    }

    /// "Pasta · done", over whatever the island shows, for `doneFlash`
    /// seconds; a newer one replaces it.
    private mutating func wentOff(_ title: String, shows: Bool, in queue: ActivityQueue, at now: Date) -> Bool {
        guard shows else { return false }
        if let id = doneID { queue.remove(id: id) }
        let line = NeoTimers.doneLine(title)
        let done = Activity(
            kind: .neoTimer, title: line.name, subtitle: line.value, symbol: Self.doneSymbol,
            priority: Self.priority, autoDismiss: Self.doneFlash, createdAt: now
        )
        queue.focusTemporarily(done)
        doneID = done.id
        return true
    }
}

/// "Show NEO's timers" (Settings → NEO): NotchHub's own preference, kept in
/// its own defaults — on unless the user switches it off. NEO's core never
/// hears of it; off, the island simply never shows NEO's timers.
public enum NeoTimerPreference {
    public static let defaultsKey = "NotchHub.neoShowsTimers"

    public static func load(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }

    public static func save(_ on: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: defaultsKey)
    }
}
