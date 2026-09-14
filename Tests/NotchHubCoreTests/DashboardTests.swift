import CoreGraphics
import Foundation
import Testing
@testable import NotchHubCore

@Suite("Dashboard")
struct DashboardTests {

    let utc = TimeZone(identifier: "UTC")!
    let us = Locale(identifier: "en_US")

    /// Friday 10 July 2026, in UTC.
    func date(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: hour, minute: minute, second: second))!
    }

    // MARK: Formatting

    @Test("the greeting follows the hour")
    func greeting() {
        #expect(DashboardFormat.greeting(hour: 9) == "good morning")
        #expect(DashboardFormat.greeting(hour: 14) == "good afternoon")
        #expect(DashboardFormat.greeting(hour: 19) == "good evening")
        #expect(DashboardFormat.greeting(hour: 2) == "good night")
    }

    @Test("the clock splits digits from AM/PM, and has no marker in 24-hour locales")
    func clock() {
        let morning = DashboardFormat.clock(date(9, 41), locale: us, timeZone: utc)
        #expect(morning.time == "9:41")
        #expect(morning.period == "AM")
        #expect(DashboardFormat.clock(date(21, 41), locale: us, timeZone: utc).period == "PM")
        let british = DashboardFormat.clock(date(21, 41), locale: Locale(identifier: "en_GB"), timeZone: utc)
        #expect(british.time == "21:41")
        #expect(british.period == nil)
    }

    @Test("the date line reads like the mockup")
    func dateLine() {
        #expect(DashboardFormat.dateLine(date(9, 41), locale: us, timeZone: utc) == "Friday, Jul 10")
    }

    @Test("event timing reads in minutes, hours, or now")
    func eventTiming() {
        let event = UpcomingEvent(title: "Design Review", startsAt: date(9, 43))
        #expect(DashboardFormat.eventTiming(event, now: date(9, 41), locale: us, timeZone: utc) == "in 2 min · 9:43")
        #expect(DashboardFormat.eventTiming(event, now: date(9, 43, 30), locale: us, timeZone: utc) == "now · 9:43")
        let later = UpcomingEvent(title: "Sync", startsAt: date(10, 46))
        #expect(DashboardFormat.eventTiming(later, now: date(9, 41), locale: us, timeZone: utc) == "in 1 hr 5 min · 10:46")
    }

    // MARK: Meeting links

    @Test("a call link is found in notes or location; other links are ignored")
    func meetingLinks() {
        let zoom = MeetingLink.find(in: [nil, "Room 4", "Join: https://us02web.zoom.us/j/123456?pwd=abc."])
        #expect(zoom?.host == "us02web.zoom.us")
        #expect(MeetingLink.find(in: ["https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com")
        #expect(MeetingLink.find(in: ["Agenda: https://example.com/doc"]) == nil)
        #expect(MeetingLink.find(in: [nil, ""]) == nil)
    }

    // MARK: Focus

    @Test("an event within the hour beats a song; a song beats a distant event")
    func focus() {
        let now = date(9, 0)
        let soon = UpcomingEvent(title: "A", startsAt: date(9, 30), joinURL: URL(string: "https://zoom.us/j/1"))
        let distant = UpcomingEvent(title: "B", startsAt: date(15, 0))
        #expect(DashboardFocus.choose(event: soon, now: now, hasNowPlaying: true) == .event(joinable: true))
        #expect(DashboardFocus.choose(event: distant, now: now, hasNowPlaying: true) == .nowPlaying)
        #expect(DashboardFocus.choose(event: distant, now: now, hasNowPlaying: false) == .event(joinable: false))
        #expect(DashboardFocus.choose(event: nil, now: now, hasNowPlaying: false) == .nothing)
    }

    // MARK: Layout

    let frame = CGRect(x: 100, y: 0, width: 440, height: 196)
    let inset: CGFloat = 32

    @Test("every control sits inside the panel and resolves to itself")
    func controlsHitTest() {
        for focus in [DashboardFocus.event(joinable: true), .nowPlaying, .nothing] {
            for (action, rect) in DashboardLayout.actions(in: frame, notchInset: inset, focus: focus) {
                #expect(frame.contains(rect), "\(action) outside the panel")
                let centre = CGPoint(x: rect.midX, y: rect.midY)
                #expect(DashboardLayout.action(at: centre, in: frame, notchInset: inset, focus: focus) == action)
            }
        }
    }

    @Test("Join exists only for a joinable event; the player only for now playing")
    func conditionalControls() {
        func actions(_ focus: DashboardFocus) -> [DashboardAction] {
            DashboardLayout.actions(in: frame, notchInset: inset, focus: focus).map(\.action)
        }
        #expect(actions(.event(joinable: true)).contains(.join))
        #expect(!actions(.event(joinable: false)).contains(.join))
        #expect(actions(.nowPlaying).contains(.openPlayer))
        #expect(!actions(.nothing).contains(.openPlayer))
        #expect(actions(.nothing) == [.settings, .timer, .dictation, .tray])
    }

    @Test("settings sits in the notch strip; quick actions along the bottom; no overlaps")
    func placement() {
        let placed = DashboardLayout.actions(in: frame, notchInset: inset, focus: .event(joinable: true))
        let settings = placed.first { $0.action == .settings }!.rect
        #expect(settings.minY >= frame.maxY - inset)
        let tray = placed.first { $0.action == .tray }!.rect
        #expect(tray.minY == frame.minY + DashboardLayout.bottomInset)
        for (i, a) in placed.enumerated() {
            for b in placed[(i + 1)...] {
                #expect(!a.rect.intersects(b.rect), "\(a.action) overlaps \(b.action)")
            }
        }
        // Clicking empty space closes the dashboard rather than hitting a control.
        #expect(DashboardLayout.action(at: CGPoint(x: frame.minX + 60, y: frame.midY), in: frame, notchInset: inset, focus: .event(joinable: true)) == nil)
    }
}
