import Foundation
import Testing
@testable import NotchHubCore

/// NEO's timers in a box, so a test can feed them inside `#expect` (which
/// cannot take a mutating call).
final class NeoTimersBox {
    var model = NeoTimers()
    @discardableResult
    func receive(_ fact: NeoFact) -> NeoTimers.Change { model.receive(fact) }
    var running: [String: NeoTimerInfo] { model.running }
    var soonest: NeoTimerInfo? { model.soonest }
    var isEmpty: Bool { model.isEmpty }
    func countdown(at now: Date) -> String? { model.countdown(at: now) }
}

@Suite("NEO's timers: the model")
struct NeoTimersModelTests {

    let t0 = Date(timeIntervalSince1970: 1_760_270_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    func timer(_ id: String, _ title: String, endsIn seconds: TimeInterval) -> NeoTimerInfo {
        NeoTimerInfo(id: "timer:\(id)", title: title, endsAt: at(seconds))
    }

    @Test("the clock: m:ss under an hour, h:mm:ss past it — whole seconds left, rounded up, never below 0:00")
    func clock() {
        #expect(NeoTimers.clock(252) == "4:12")
        #expect(NeoTimers.clock(9) == "0:09")
        #expect(NeoTimers.clock(0) == "0:00")
        #expect(NeoTimers.clock(600) == "10:00")
        #expect(NeoTimers.clock(3_852) == "1:04:12")
        // A timer that opens on 5:00 shows 5:00, and 0:01 through its last second.
        #expect(NeoTimers.secondsLeft(until: at(300), at: t0) == 300)
        #expect(NeoTimers.secondsLeft(until: at(251.2), at: t0) == 252)
        #expect(NeoTimers.secondsLeft(until: at(0.2), at: t0) == 1)
        // Already past (restored late, after the Mac slept): 0:00, never negative.
        #expect(NeoTimers.secondsLeft(until: at(-90), at: t0) == 0)
        // Nothing the core says can overflow the clock.
        #expect(NeoTimers.secondsLeft(until: Date(timeIntervalSince1970: 1e300), at: t0) == Int(NeoTimers.longestCountdown))
        #expect(NeoTimers.clock(Int(NeoTimers.longestCountdown)) == "99:59:59")
    }

    @Test("the island's line: the name and the clock; a long name is cut so the clock always shows")
    func titles() {
        #expect(NeoTimers.countdownTitle(timer("a", "Pasta", endsIn: 252), at: t0) == "Pasta 4:12")
        #expect(NeoTimers.countdownTitle(timer("a", "Timer", endsIn: 61), at: t0) == "Timer 1:01")
        #expect(NeoTimers.countdownTitle(timer("a", "Pasta", endsIn: -5), at: t0) == "Pasta 0:00")
        #expect(NeoTimers.doneTitle("Pasta") == "Pasta · done")
        #expect(NeoTimers.countdownLine(timer("a", "Pasta", endsIn: 252), at: t0) == NeoTimerLine(name: "Pasta", value: "4:12"))
        #expect(NeoTimers.doneLine("Pasta") == NeoTimerLine(name: "Pasta", value: "· done"))
        #expect(NeoTimers.label("Pasta") == "Pasta")
        #expect(NeoTimers.label("") == "Timer" && NeoTimers.label("   ") == "Timer")
        let long = "Take the bread out of the oven now"
        let cut = NeoTimers.label(long)
        #expect(cut.count <= NeoTimers.labelLimit && cut.hasSuffix("…"))
        // Cut at a word's end when the limit falls on a space: no "bread …".
        #expect(cut == "Take the bread…")
        #expect(NeoTimers.countdownTitle(timer("a", long, endsIn: 252), at: t0).hasSuffix(" 4:12"))
        // Exactly at the limit: untouched.
        let sixteen = String(repeating: "x", count: NeoTimers.labelLimit)
        #expect(NeoTimers.label(sixteen) == sixteen)
    }

    @Test("a hello replaces every timer; present upserts by id; end removes by id")
    func lifecycle() {
        let timers = NeoTimersBox()
        let pasta = timer("3f2a9c1b7d4e", "Pasta", endsIn: 252)
        let tea = timer("a1b2c3d4e5f6", "Tea", endsIn: 900)
        #expect(timers.receive(.neoTimers([pasta, tea])) == .changed)
        #expect(timers.running.count == 2 && timers.soonest == pasta)
        // The same hello again (a reconnect): nothing changed.
        #expect(timers.receive(.neoTimers([tea, pasta])) == .none)
        // A later hello is the whole truth: what it does not list is gone.
        #expect(timers.receive(.neoTimers([tea])) == .changed)
        #expect(timers.running.count == 1 && timers.soonest == tea)

        // Present: upsert, repeated freely (a restore after a restart).
        #expect(timers.receive(.neoTimer(pasta)) == .changed)
        #expect(timers.receive(.neoTimer(pasta)) == .none)
        let later = NeoTimerInfo(id: pasta.id, title: "Pasta", endsAt: at(400))
        #expect(timers.receive(.neoTimer(later)) == .changed)
        #expect(timers.running[pasta.id] == later && timers.soonest == later)

        // Cancelled: gone at once, no "done".
        #expect(timers.receive(.neoTimerEnd(id: pasta.id, title: "Pasta", done: false)) == .changed)
        #expect(timers.running[pasta.id] == nil)
        #expect(timers.receive(.neoTimerEnd(id: pasta.id, title: "Pasta", done: false)) == .none)
        // Went off: gone, and the "done" names it as the island knew it.
        #expect(timers.receive(.neoTimerEnd(id: tea.id, title: "ignored", done: true)) == .wentOff(title: "Tea"))
        #expect(timers.isEmpty && timers.soonest == nil)
        // One the island never heard of still went off: the core's own words.
        #expect(timers.receive(.neoTimerEnd(id: "timer:ffffffffffff", title: "Eggs", done: true)) == .wentOff(title: "Eggs"))
        // An empty hello: none.
        #expect(timers.receive(.neoTimers([])) == .none)
    }

    @Test("the core going away takes every timer with it; nothing else from NEO touches them")
    func otherFacts() {
        let timers = NeoTimersBox()
        timers.receive(.neoTimers([timer("a", "Pasta", endsIn: 60)]))
        for fact: NeoFact in [.connected(true), .state(.listening), .note("n"), .error("e"), .woke, .confirmDone("x"),
                              .transcript(role: .user, text: "cancel the pasta timer", final: true), .card(.song, open: true)] {
            #expect(timers.receive(fact) == .none, "\(fact)")
        }
        #expect(timers.running.count == 1)
        #expect(timers.receive(.connected(false)) == .changed)
        #expect(timers.isEmpty)
        #expect(timers.receive(.connected(false)) == .none)
    }

    @Test("the soonest wins the island, ties broken by id; the countdown is nil without a timer")
    func soonest() {
        let timers = NeoTimersBox()
        #expect(timers.countdown(at: t0) == nil)
        timers.receive(.neoTimers([timer("b", "Tea", endsIn: 900), timer("c", "Eggs", endsIn: 420), timer("a", "Rice", endsIn: 420)]))
        #expect(timers.soonest?.id == "timer:a")
        #expect(timers.countdown(at: t0) == "Rice 7:00")
        #expect(timers.countdown(at: at(1)) == "Rice 6:59")
    }

    @Test("a flood of timers is capped, so a confused core cannot grow the island's memory without bound")
    func cap() {
        let timers = NeoTimersBox()
        timers.receive(.neoTimers((0..<500).map { timer(String($0), "T", endsIn: Double($0)) }))
        #expect(timers.running.count == NeoTimers.maxTimers)
        for i in 500..<600 { timers.receive(.neoTimer(timer(String(i), "T", endsIn: 1))) }
        #expect(timers.running.count == NeoTimers.maxTimers)
        // A known one still updates.
        #expect(timers.receive(.neoTimer(timer("0", "Renamed", endsIn: 0))) == .changed)
    }
}

@Suite("NEO's timers: what the core says")
struct NeoTimerInfoTests {

    @Test("an entry needs an id and a real number of seconds; the title is one plain line of at most 40 characters")
    func payload() throws {
        let entry = try #require(NeoTimerInfo(payload: ["id": "timer:3f2a9c1b7d4e", "title": "Pasta", "ends_at": 1_760_270_252.0]))
        #expect(entry == NeoTimerInfo(id: "timer:3f2a9c1b7d4e", title: "Pasta", endsAt: Date(timeIntervalSince1970: 1_760_270_252)))
        // An integer number of seconds is a number too.
        #expect(NeoTimerInfo(payload: ["id": "timer:a", "title": "x", "ends_at": 1_760_270_252])?.endsAt == Date(timeIntervalSince1970: 1_760_270_252))
        // No name: "Timer".
        #expect(NeoTimerInfo(payload: ["id": "timer:a", "ends_at": 1.0])?.title == "Timer")
        #expect(NeoTimerInfo(payload: ["id": "timer:a", "title": "  \n ", "ends_at": 1.0])?.title == "Timer")
        #expect(NeoTimerInfo(payload: ["id": "timer:a", "title": 7, "ends_at": 1.0])?.title == "Timer")
        // One line, collapsed, capped — never layout, never a direction override.
        #expect(NeoTimerInfo(payload: ["id": "timer:a", "title": "Pasta\n\tnow\r\n", "ends_at": 1.0])?.title == "Pasta now")
        #expect(NeoTimerInfo(payload: ["id": "timer:a", "title": "\u{202E}atsaP", "ends_at": 1.0])?.title == "atsaP")
        #expect(NeoTimerInfo(payload: ["id": "timer:a", "title": String(repeating: "y", count: 90), "ends_at": 1.0])?.title.count == 40)
        // Markdown is just characters: rendered as text, never as styling.
        #expect(NeoTimerInfo(payload: ["id": "timer:a", "title": "**bold** [x](y)", "ends_at": 1.0])?.title == "**bold** [x](y)")

        // Nothing usable: no timer.
        for bad: [String: Any] in [
            ["title": "Pasta", "ends_at": 1.0],
            ["id": "", "title": "Pasta", "ends_at": 1.0],
            ["id": 12, "title": "Pasta", "ends_at": 1.0],
            ["id": String(repeating: "x", count: 65), "ends_at": 1.0],
            ["id": "timer:a", "title": "Pasta"],
            ["id": "timer:a", "ends_at": "1760270252"],
            ["id": "timer:a", "ends_at": true],
            ["id": "timer:a", "ends_at": Double.nan],
            ["id": "timer:a", "ends_at": Double.infinity],
        ] {
            #expect(NeoTimerInfo(payload: bad) == nil, "\(bad)")
        }
    }
}

@Suite("NEO's timers on the island")
struct NeoTimerSurfaceTests {

    let t0 = Date(timeIntervalSince1970: 1_760_270_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    let pasta = NeoTimerInfo(id: "timer:3f2a9c1b7d4e", title: "Pasta", endsAt: Date(timeIntervalSince1970: 1_760_270_252))
    let tea = NeoTimerInfo(id: "timer:a1b2c3d4e5f6", title: "Tea", endsAt: Date(timeIntervalSince1970: 1_760_270_900.5))

    /// NEO's timers, the surface and a queue, driven the way the app does.
    final class Rig {
        var timers = NeoTimers()
        var surface = NeoTimerSurface()
        let queue = ActivityQueue()
        var shows = true

        @discardableResult
        func receive(_ fact: NeoFact, at now: Date) -> Bool {
            let change = timers.receive(fact)
            return surface.apply(change, timers: timers, shows: shows, in: queue, at: now)
        }

        @discardableResult
        func tick(at now: Date) -> Bool {
            queue.tick(now: now)
            return surface.sync(timers, shows: shows, in: queue, at: now)
        }

        var neo: [Activity] { queue.all.filter { $0.kind == .neoTimer } }
    }

    @Test("no timer, nothing on the island — however long it ticks")
    func nothing() {
        let rig = Rig()
        #expect(!rig.tick(at: t0) && !rig.tick(at: at(30)))
        #expect(rig.queue.isEmpty)
        #expect(!rig.receive(.connected(true), at: t0) && !rig.receive(.state(.listening), at: t0) && !rig.receive(.neoTimers([]), at: t0))
        #expect(rig.queue.isEmpty)
    }

    @Test("one countdown, of NEO's own kind, at NotchHub's timer priority; it ticks down in place")
    func countdown() throws {
        let rig = Rig()
        #expect(rig.receive(.neoTimers([pasta]), at: t0))
        let shown = try #require(rig.queue.current)
        #expect(shown.kind == .neoTimer && shown.kind != .timer)
        // The name and the clock, drawn as two: the name may be cut, the clock never.
        #expect(shown.title == "Pasta" && shown.subtitle == "4:12" && shown.compactText == "Pasta 4:12")
        #expect(shown.resolvedSymbol == "timer" && shown.priority == 70 && shown.autoDismiss == 0)
        #expect(!shown.canExpand && !shown.expandsOnHover)
        // A second later: the same surface, a second less — no new activity, no new birth date.
        rig.tick(at: at(1))
        let next = try #require(rig.queue.current)
        #expect(next.id == shown.id && next.createdAt == shown.createdAt && next.compactText == "Pasta 4:11")
        #expect(rig.queue.all.count == 1)
        // Half a second later the clock has not moved: nothing to redraw.
        #expect(!rig.tick(at: at(1.4)))
        // Past its end, before the core says it went off: 0:00.
        rig.tick(at: at(260))
        #expect(rig.queue.current?.compactText == "Pasta 0:00")
    }

    @Test("several timers: the island shows the soonest, and the next one once it is over")
    func soonestFirst() {
        let rig = Rig()
        rig.receive(.neoTimers([tea]), at: t0)
        #expect(rig.queue.current?.compactText == "Tea 15:01")
        rig.receive(.neoTimer(pasta), at: at(2))
        #expect(rig.neo.count == 1 && rig.queue.current?.compactText == "Pasta 4:10")
        rig.receive(.neoTimerEnd(id: pasta.id, title: "Pasta", done: false), at: at(3))
        #expect(rig.neo.count == 1 && rig.queue.current?.compactText == "Tea 14:58")
    }

    @Test("cancelled: off the island at once; the last one gone, the island is empty again")
    func cancelled() {
        let rig = Rig()
        rig.receive(.neoTimers([pasta]), at: t0)
        #expect(rig.receive(.neoTimerEnd(id: pasta.id, title: "Pasta", done: false), at: at(5)))
        #expect(rig.queue.isEmpty)
        #expect(!rig.tick(at: at(6)) && rig.queue.isEmpty)
    }

    @Test("went off: “Pasta · done” takes the island for about 5 s, then hands it back")
    func wentOff() throws {
        let rig = Rig()
        rig.receive(.neoTimers([pasta, tea]), at: t0)
        #expect(rig.receive(.neoTimerEnd(id: pasta.id, title: "Pasta", done: true), at: at(252.3)))
        let flash = try #require(rig.queue.current)
        #expect(flash.kind == .neoTimer && flash.compactText == "Pasta · done" && flash.autoDismiss == NeoTimerSurface.doneFlash)
        #expect(flash.title == "Pasta" && flash.subtitle == "· done" && flash.resolvedSymbol == NeoTimerSurface.doneSymbol)
        #expect(NeoTimerSurface.doneFlash == 5)
        rig.tick(at: at(254))
        #expect(rig.queue.current?.compactText == "Pasta · done")
        // Over: back to the timer still running.
        rig.tick(at: at(257.4))
        #expect(rig.queue.current?.compactText == "Tea 10:44")
        #expect(rig.neo.count == 1)
        // The last one going off leaves nothing once its moment is over.
        rig.receive(.neoTimerEnd(id: tea.id, title: "Tea", done: true), at: at(900.6))
        #expect(rig.queue.current?.compactText == "Tea · done")
        rig.tick(at: at(906))
        #expect(rig.queue.isEmpty)
    }

    @Test("two going off in a row: one “done” at a time, the newest")
    func twoDone() {
        let rig = Rig()
        rig.receive(.neoTimers([pasta, tea]), at: t0)
        rig.receive(.neoTimerEnd(id: pasta.id, title: "Pasta", done: true), at: at(10))
        rig.receive(.neoTimerEnd(id: tea.id, title: "Tea", done: true), at: at(11))
        #expect(rig.neo.count == 1 && rig.queue.current?.compactText == "Tea · done")
    }

    @Test("beside NotchHub's own focus timer: two surfaces, no flapping — each tick shows the same one")
    func besideFocusTimer() throws {
        let rig = Rig()
        // NotchHub's focus timer, upserted twice a second as the bridge does.
        func focusTick(_ now: Date, remaining: TimeInterval) {
            rig.queue.upsert(Activity(kind: .timer, title: "Focus", symbol: "timer", elapsed: remaining, createdAt: now))
        }
        focusTick(t0, remaining: 1500)
        rig.receive(.neoTimers([pasta]), at: at(0.25))
        var seen: Set<UUID> = []
        for step in 1...40 {
            let now = at(Double(step) * 0.5)
            focusTick(now, remaining: 1500 - Double(step) * 0.5)
            rig.tick(at: now)
            let current = try #require(rig.queue.current)
            seen.insert(current.id)
            #expect(rig.queue.all.count == 2 && rig.queue.stackCount == 1)
            #expect(rig.queue.all.filter { $0.kind == .timer }.count == 1 && rig.neo.count == 1)
        }
        #expect(seen.count == 1)
        // NEO's "done" is news: it takes the island over the focus timer, then gives it back.
        rig.receive(.neoTimerEnd(id: pasta.id, title: "Pasta", done: true), at: at(20.2))
        #expect(rig.queue.current?.compactText == "Pasta · done")
        focusTick(at(26), remaining: 1474)
        rig.tick(at: at(26))
        #expect(rig.queue.current?.kind == .timer && rig.neo.isEmpty)
    }

    @Test("“Show NEO's timers” off: never on the island; switched off, they leave; on again, they are back")
    func switchedOff() {
        let rig = Rig()
        rig.shows = false
        #expect(!rig.receive(.neoTimers([pasta]), at: t0))
        #expect(!rig.tick(at: at(1)) && rig.queue.isEmpty)
        #expect(!rig.receive(.neoTimerEnd(id: "timer:x", title: "Eggs", done: true), at: at(2)))
        #expect(rig.queue.isEmpty)
        rig.shows = true
        #expect(rig.tick(at: at(3)))
        #expect(rig.queue.current?.compactText == "Pasta 4:09")
        rig.receive(.neoTimerEnd(id: "timer:y", title: "Eggs", done: true), at: at(4))
        #expect(rig.neo.count == 2)
        rig.shows = false
        #expect(rig.tick(at: at(5)))
        #expect(rig.queue.isEmpty)
    }

    @Test("the core gone: every NEO timer leaves the island, the “done” moment too")
    func disconnected() {
        let rig = Rig()
        rig.receive(.neoTimers([pasta, tea]), at: t0)
        rig.receive(.neoTimerEnd(id: pasta.id, title: "Pasta", done: true), at: at(1))
        #expect(rig.neo.count == 2)
        rig.shows = false // NEO is no longer there
        #expect(rig.receive(.connected(false), at: at(2)))
        #expect(rig.queue.isEmpty && rig.timers.isEmpty)
    }

    @Test("sent back to idle by hand: the countdown stays away until NEO's timers change")
    func dismissed() {
        let rig = Rig()
        rig.receive(.neoTimers([pasta]), at: t0)
        rig.queue.removeAll()
        rig.surface.dismiss()
        #expect(!rig.tick(at: at(1)) && rig.queue.isEmpty)
        #expect(!rig.tick(at: at(30)) && rig.queue.isEmpty)
        // A new timer is news again.
        #expect(rig.receive(.neoTimer(tea), at: at(31)))
        #expect(rig.queue.current?.compactText == "Pasta 3:41")
    }

    @Test("the surface never touches what isn't NEO's")
    func leavesOthersAlone() {
        let rig = Rig()
        let song = Activity.music(title: "Midnight City", artist: "M83")
        let greeting = Activity(kind: .custom, title: "Happy Diwali", autoDismiss: 0)
        rig.queue.push(song)
        rig.queue.push(greeting)
        rig.receive(.neoTimers([pasta]), at: t0)
        rig.receive(.neoTimerEnd(id: pasta.id, title: "Pasta", done: false), at: at(1))
        rig.receive(.connected(false), at: at(2))
        let left: Set<UUID> = Set(rig.queue.all.map(\.id))
        #expect(left == [song.id, greeting.id])
    }
}

@Suite("Settings → NEO → Show NEO's timers")
struct NeoTimerSettingTests {

    @Test("on unless switched off; its switch works whenever NEO is on in the notch, running or not")
    func model() {
        let away = NeoSettingsModel(featureOn: true, connected: false, shell: nil)
        #expect(away.showsTimers && away.isEnabled(.showTimers(false)) && away.isEnabled(.showTimers(true)))
        let off = NeoSettingsModel(featureOn: true, connected: true, shell: nil, showsTimers: false)
        #expect(!off.showsTimers && off.isEnabled(.showTimers(true)))
        #expect(away.timersCaption != off.timersCaption)
        let featureOff = NeoSettingsModel(featureOn: false, connected: true, shell: nil)
        #expect(!featureOff.isEnabled(.showTimers(true)) && !featureOff.isEnabled(.showTimers(false)))
        // NotchHub's own preference: nothing goes to NEO.app or its core.
        #expect(NeoSettingsIntent.showTimers(false).shellAction == nil && NeoSettingsIntent.showTimers(false).setting == nil)
    }

    @Test("kept in NotchHub's own defaults: on when never set, then what was chosen")
    func preference() throws {
        let suite = "NotchHubTests.neoTimers.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(NeoTimerPreference.load(from: defaults))
        NeoTimerPreference.save(false, to: defaults)
        #expect(!NeoTimerPreference.load(from: defaults))
        NeoTimerPreference.save(true, to: defaults)
        #expect(NeoTimerPreference.load(from: defaults))
        // Something that is not a switch: the default.
        defaults.set("no", forKey: NeoTimerPreference.defaultsKey)
        #expect(NeoTimerPreference.load(from: defaults))
    }
}
