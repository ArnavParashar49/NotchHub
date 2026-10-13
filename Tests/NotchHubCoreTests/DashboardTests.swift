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
        // With nothing to focus on, only the settings control and the quick
        // actions are there. Order-independent — what matters visually is the
        // left-to-right placement, which `quickActionOrder` checks.
        #expect(Set(actions(.nothing)) == [.settings, .lidAwake, .timer, .teleprompter, .camera, .tray])
    }

    @Test("the quick actions read left to right, with the Tray anchored at the trailing inset")
    func quickActionOrder() {
        let placed = DashboardLayout.actions(in: frame, notchInset: inset, focus: .nothing)
        let bar: [DashboardAction] = [.lidAwake, .timer, .teleprompter, .camera, .tray]
        #expect(DashboardLayout.quickActions == bar)
        let rects = bar.map { action in placed.first { $0.action == action }!.rect }
        for (index, rect) in rects.enumerated().dropFirst() {
            #expect(rect.minX > rects[index - 1].minX, "\(bar[index]) is out of order")
            #expect(rect.minX >= rects[index - 1].maxX, "\(bar[index]) overlaps the chip before it")
        }
        // The Tray stays where it has always been, however many chips join it.
        #expect(rects.last!.maxX == frame.maxX - DashboardLayout.horizontalInset)
        #expect(rects.allSatisfy { frame.contains($0) })
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

    @Test("the lid, timer, teleprompter and camera are 28-pt glyph chips; the Tray keeps 56; the row is 10 pt narrower than with the worded Timer")
    func chipWidths() {
        let placed = DashboardLayout.actions(in: frame, notchInset: inset, focus: .nothing)
        func rect(_ action: DashboardAction) -> CGRect { placed.first { $0.action == action }!.rect }
        for action in [DashboardAction.lidAwake, .timer, .teleprompter, .camera] {
            #expect(rect(action).width == 28, "\(action) is not a glyph chip")
            #expect(DashboardLayout.chipWidth(action) == DashboardLayout.glyphChipWidth)
        }
        #expect(rect(.tray).width == 56)
        for action in DashboardLayout.quickActions {
            #expect(rect(action).height == DashboardLayout.barHeight)
            #expect(rect(action).minY == frame.minY + DashboardLayout.bottomInset)
        }
        // Evenly spaced: one chip gap between each pair.
        let rects = DashboardLayout.quickActions.map(rect)
        for (index, r) in rects.enumerated().dropFirst() {
            #expect(r.minX - rects[index - 1].maxX == DashboardLayout.chipSpacing)
        }
        // The whole row, lid chip to Tray: 4 × 28 + 56 + 4 gaps of 10.
        #expect(DashboardLayout.quickActionsWidth == 208)
        #expect(rects.last!.maxX - rects.first!.minX == DashboardLayout.quickActionsWidth)
        // Before: Timer 76 + teleprompter 28 + camera 28 + Tray 56 + 3 gaps.
        #expect(218 - DashboardLayout.quickActionsWidth == 10)
    }

    /// The dashboard on the narrowest notched screen (a 13-inch MacBook Air
    /// at "Larger Text", 1024 pt wide: 30 % of it), a 14-inch at its 1352-pt
    /// setting, and the widest (capped at 440).
    static let panelWidths: [CGFloat] = [1024 * NotchGeometry.interactiveWidthFraction, 1352 * NotchGeometry.interactiveWidthFraction,
                                         NotchGeometry.interactiveMaxWidth]

    @Test("at every panel width down to the narrowest: the lid chip leftmost, nothing overlapping, a click on any part of a chip lands on it and a click between chips on none")
    func chipsAtEveryWidth() {
        for width in Self.panelWidths {
            let panel = CGRect(x: 300, y: 600, width: width, height: NotchGeometry.interactiveHeight)
            for focus in [DashboardFocus.event(joinable: true), .nowPlaying, .nothing] {
                let placed = DashboardLayout.actions(in: panel, notchInset: inset, focus: focus)
                for (i, a) in placed.enumerated() {
                    #expect(panel.contains(a.rect), "\(a.action) outside the \(width)-pt panel")
                    for b in placed[(i + 1)...] {
                        #expect(!a.rect.intersects(b.rect), "\(a.action) overlaps \(b.action) at \(width) pt")
                    }
                }
                let chips = DashboardLayout.quickActions.map { action in placed.first { $0.action == action }!.rect }
                // The lid chip is the leftmost thing on the bar's row of chips,
                // and the row stays clear of the leading inset — the status
                // (battery, focus, a live mic / camera) has what is left.
                #expect(chips.allSatisfy { $0.minX >= chips[0].minX })
                #expect(chips[0].minX >= panel.minX + DashboardLayout.horizontalInset + 40)
                for (action, rect) in zip(DashboardLayout.quickActions, chips) {
                    for point in [CGPoint(x: rect.midX, y: rect.midY), CGPoint(x: rect.minX + 1, y: rect.minY + 1),
                                  CGPoint(x: rect.maxX - 1, y: rect.maxY - 1)] {
                        #expect(DashboardLayout.action(at: point, in: panel, notchInset: inset, focus: focus) == action)
                    }
                }
                for (left, right) in zip(chips, chips.dropFirst()) {
                    let gap = CGPoint(x: (left.maxX + right.minX) / 2, y: left.midY)
                    #expect(DashboardLayout.action(at: gap, in: panel, notchInset: inset, focus: focus) == nil)
                }
            }
        }
    }

    // MARK: The lid chip

    @Test("the lid chip: switch off is plain — unless sleep is still turned off, the dot; on and keeping the Mac awake is lit; on but paused or switching is the dot")
    func lidChipLook() {
        func chip(_ status: LidSettingsModel.Status, on: Bool = true) -> DashboardLidChip {
            DashboardLidChip(LidSettingsModel(settings: LidAwakeSettings(enabled: on), status: status, helperInstalled: true))
        }
        // Switch off and the Mac sleeps when closed: plain, like any idle chip.
        let sleeps: [LidSettingsModel.Status] = [
            .notManaged, .normal, .switching(.on), .switching(.off), .switching(.settingUp), .switching(.removing),
            .held(.onBattery), .held(.batteryLow(floor: 20)), .held(.powerUnknown), .held(.noAppsChosen), .held(.appsClosed),
            .needsYou,
        ]
        for status in sleeps {
            #expect(chip(status, on: false) == .off, "\(status)")
        }
        // Switch off but a closed lid would NOT sleep the Mac — NotchHub's
        // SleepDisabled 1 that could not be put back (a cancelled dialog), or
        // one set outside NotchHub: never the plain idle look; the dot sends
        // the eye to Settings (Restore normal sleep…).
        for status in [LidSettingsModel.Status.stillOff, .outside, .awake] {
            #expect(chip(status, on: false) == .waiting, "\(status)")
        }
        // On and NotchHub's SleepDisabled holds: lit.
        #expect(chip(.awake) == .awake)
        #expect(chip(.stillOff) == .awake)
        // On, but the Mac sleeps when closed for now: the dot.
        for hold in [LidAwakeHold.onBattery, .batteryLow(floor: 25), .powerUnknown, .noAppsChosen, .appsClosed] {
            #expect(chip(.held(hold)) == .waiting, "\(hold)")
        }
        for status in [LidSettingsModel.Status.needsYou, .switching(.on), .switching(.settingUp), .switching(.off), .outside, .normal, .notManaged] {
            #expect(chip(status) == .waiting, "\(status)")
        }
    }

    @Test("a click on the lid chip is the Settings switch's own tap — none while a change is in flight or the launch doesn't manage sleep")
    func lidChipClick() {
        let off = LidSettingsModel(settings: LidAwakeSettings(), status: .normal)
        #expect(DashboardLidChip.click(off) == .setEnabled(true))
        let awake = LidSettingsModel(settings: LidAwakeSettings(enabled: true), status: .awake, helperInstalled: true)
        #expect(DashboardLidChip.click(awake) == .setEnabled(false))
        let paused = LidSettingsModel(settings: LidAwakeSettings(enabled: true), status: .held(.onBattery), helperInstalled: true)
        #expect(DashboardLidChip.click(paused) == .setEnabled(false))
        let needsYou = LidSettingsModel(settings: LidAwakeSettings(enabled: true), status: .needsYou, helperInstalled: false)
        #expect(DashboardLidChip.click(needsYou) == .setEnabled(false))
        // The dot with the switch off (sleep still turned off): the click is
        // still the switch's own tap — on — never a different intent.
        for status in [LidSettingsModel.Status.stillOff, .outside] {
            let dotted = LidSettingsModel(settings: LidAwakeSettings(), status: status, helperInstalled: true)
            #expect(DashboardLidChip(dotted) == .waiting && DashboardLidChip.click(dotted) == .setEnabled(true), "\(status)")
        }
        let busy = LidSettingsModel(settings: LidAwakeSettings(enabled: true), status: .switching(.on), busy: true)
        #expect(DashboardLidChip.click(busy) == nil)
        #expect(DashboardLidChip.click(LidSettingsModel(settings: LidAwakeSettings(), status: .notManaged)) == nil)
    }

    @Test("the lid chip follows the engine: lit exactly while it keeps the Mac awake with the switch on")
    func lidChipFollowsEngine() {
        let t0 = Date(timeIntervalSince1970: 1_760_300_000)
        let ac = PowerSnapshot(onAC: true, batteryPercent: 80)
        var engine = LidAwakeEngine(settings: LidAwakeSettings(), record: LidAwakeRecord(), helperInstalled: true)
        _ = engine.launch(observed: false, power: ac, running: [], helperInstalled: true, now: t0)
        func chip() -> DashboardLidChip { DashboardLidChip(LidSettingsModel(engine: engine)) }
        #expect(chip() == .off && !engine.isKeepingAwake)

        // The click: the switch goes on and sleep is turned off through the helper.
        #expect(DashboardLidChip.click(LidSettingsModel(engine: engine)) == .setEnabled(true))
        _ = engine.setEnabled(true, now: t0)
        #expect(engine.busy && chip() == .waiting)
        _ = engine.finished(outcome: .done, observed: true, helperInstalled: true, helperWorked: true, askedAdmin: false, now: t0)
        #expect(engine.isKeepingAwake && chip() == .awake)

        // Unplugged: the guard puts sleep back — the dot, not the light.
        _ = engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 90), now: t0)
        #expect(chip() == .waiting)
        _ = engine.finished(outcome: .done, observed: false, helperInstalled: true, helperWorked: true, askedAdmin: false, now: t0)
        #expect(!engine.isKeepingAwake && LidSettingsModel(engine: engine).status == .held(.onBattery) && chip() == .waiting)

        // The click again: the switch goes off.
        #expect(DashboardLidChip.click(LidSettingsModel(engine: engine)) == .setEnabled(false))
        _ = engine.setEnabled(false, now: t0)
        #expect(!engine.settings.enabled && chip() == .off)
    }
}
