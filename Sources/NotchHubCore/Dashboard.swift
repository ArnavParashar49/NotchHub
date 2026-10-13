import CoreGraphics
import Foundation

// MARK: - Upcoming event

/// The next calendar event, as the dashboard shows it.
public struct UpcomingEvent: Equatable, Sendable {
    public var title: String
    public var startsAt: Date
    /// A video-call link found on the event (Zoom, Meet, Teams, …) — what the
    /// dashboard's Join button opens.
    public var joinURL: URL?

    public init(title: String, startsAt: Date, joinURL: URL? = nil) {
        self.title = title
        self.startsAt = startsAt
        self.joinURL = joinURL
    }
}

/// Finds a joinable video-call link in an event's URL, location or notes.
public enum MeetingLink {

    /// Hosts whose links join a call.
    static let hosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "facetime.apple.com",
    ]

    /// The address of a Google Meet CALL ("https://meet.google.com/abc-defg-hij"),
    /// or `nil` for Meet's home, landing and post-call pages.
    public static func googleMeetCall(in urlString: String) -> String? {
        guard let url = URL(string: urlString), url.host?.lowercased() == "meet.google.com",
              let code = url.path.split(separator: "/").first.map(String.init),
              code.range(of: #"^[a-z]{3}-[a-z]{4}-[a-z]{3}$"#, options: .regularExpression) != nil else { return nil }
        return "https://meet.google.com/\(code)"
    }

    public static func find(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                guard let url = match.url,
                      let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
                      let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }
}

// MARK: - Formatting

/// The dashboard's words and numbers.
public enum DashboardFormat {

    public static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<12: return "good morning"
        case 12..<17: return "good afternoon"
        case 17..<22: return "good evening"
        default: return "good night"
        }
    }

    /// The clock split into its digits and its AM/PM marker, so the marker can
    /// be set small beside large digits. `period` is nil in 24-hour locales.
    public static func clock(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> (time: String, period: String?) {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        let full = formatter.string(from: date)
        for symbol in [formatter.amSymbol, formatter.pmSymbol].compactMap({ $0 }) where !symbol.isEmpty {
            if let range = full.range(of: symbol) {
                var time = full
                time.removeSubrange(range)
                return (time.trimmingCharacters(in: .whitespacesAndNewlines), symbol)
            }
        }
        return (full, nil)
    }

    /// "Friday, Jul 11".
    public static func dateLine(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return formatter.string(from: date)
    }

    /// "in 2 min · 9:43", "now · 9:43", "in 1 hr 5 min · 10:46".
    public static func eventTiming(_ event: UpcomingEvent, now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let minutes = Int((event.startsAt.timeIntervalSince(now) / 60).rounded(.up))
        let when: String
        if minutes <= 0 {
            when = "now"
        } else if minutes < 60 {
            when = "in \(minutes) min"
        } else {
            let hours = minutes / 60
            let rest = minutes % 60
            when = rest == 0 ? "in \(hours) hr" : "in \(hours) hr \(rest) min"
        }
        return "\(when) · \(clock(event.startsAt, locale: locale, timeZone: timeZone).time)"
    }
}

// MARK: - Focus

/// What the dashboard's right-hand column is about.
public enum DashboardFocus: Equatable, Sendable {
    /// The next calendar event; `joinable` when it carries a call link.
    case event(joinable: Bool)
    /// The track that is playing.
    case nowPlaying
    /// Nothing scheduled and nothing playing.
    case nothing

    /// An event starting within this window outranks a playing song.
    public static let soonWindow: TimeInterval = 60 * 60

    public static func choose(event: UpcomingEvent?, now: Date, hasNowPlaying: Bool) -> DashboardFocus {
        if let event, event.startsAt.timeIntervalSince(now) <= soonWindow {
            return .event(joinable: event.joinURL != nil)
        }
        if hasNowPlaying { return .nowPlaying }
        if let event { return .event(joinable: event.joinURL != nil) }
        return .nothing
    }
}

// MARK: - Layout

/// Something the dashboard does when clicked.
public enum DashboardAction: String, CaseIterable, Sendable {
    case settings
    case join
    case openPlayer
    /// "Keep working with the lid closed": the same switch as Settings →
    /// Lid Closed (`DashboardLidChip`).
    case lidAwake
    case timer
    case teleprompter
    case camera
    case tray
}

/// The geometry of the dashboard's clickable areas.
///
/// `DashboardView` draws from these numbers and the window hit-tests clicks
/// against them — the island never takes key focus, so the dashboard's
/// controls are drawn, not SwiftUI buttons. Both sides share this type so a
/// control cannot draw in one place and accept clicks in another.
public enum DashboardLayout {
    public static let horizontalInset: CGFloat = 24
    /// Gap between the notch line and the first row.
    public static let topInset: CGFloat = 12
    public static let bottomInset: CGFloat = 14
    /// Where the right column starts, as a fraction of the panel width.
    public static let rightColumnFraction: CGFloat = 0.54

    public static let labelRowHeight: CGFloat = 16
    public static let titleRowHeight: CGFloat = 20
    public static let detailRowHeight: CGFloat = 18
    /// Indent of the detail line and Join button, aligning them with the title
    /// text after its dot.
    public static let detailIndent: CGFloat = 12
    public static let joinGap: CGFloat = 6
    public static let joinSize = CGSize(width: 72, height: 24)

    public static let barHeight: CGFloat = 24
    public static let chipSpacing: CGFloat = 10
    /// The glyph-only chips: the lid, the timer, the teleprompter and the
    /// camera. (The timer's chip is a glyph too: a running stopwatch shows
    /// on the compact island, so the chip only lights up.)
    public static let glyphChipWidth: CGFloat = 28
    /// The Tray's chip, which carries its count.
    public static let trayChipWidth: CGFloat = 56

    /// The quick actions on the bottom bar, left to right. They are placed
    /// from the trailing inset, so the Tray stays put as chips join it.
    public static let quickActions: [DashboardAction] = [.lidAwake, .timer, .teleprompter, .camera, .tray]

    /// A quick action's chip width (`0` for an action that isn't on the bar).
    public static func chipWidth(_ action: DashboardAction) -> CGFloat {
        switch action {
        case .tray: return trayChipWidth
        case .lidAwake, .timer, .teleprompter, .camera: return glyphChipWidth
        case .settings, .join, .openPlayer: return 0
        }
    }

    /// The row of chips, the gaps between them included: 4 × 28 + 56 +
    /// 4 × 10 = 208 pt — 10 pt less than the worded 76-pt Timer chip took
    /// before the lid chip joined, so the status on the left has more room.
    public static var quickActionsWidth: CGFloat {
        quickActions.map(chipWidth).reduce(0, +) + chipSpacing * CGFloat(quickActions.count - 1)
    }

    /// The "···" settings control, in the notch strip beside the cutout.
    public static let moreSize = CGSize(width: 32, height: 22)

    /// Every clickable area for a dashboard frame in AppKit coordinates
    /// (origin bottom-left). Content starts below the notch strip, which
    /// occupies the top `notchInset` points.
    public static func actions(in frame: CGRect, notchInset: CGFloat, focus: DashboardFocus) -> [(action: DashboardAction, rect: CGRect)] {
        var result: [(action: DashboardAction, rect: CGRect)] = []

        result.append((.settings, CGRect(
            x: frame.maxX - horizontalInset - moreSize.width,
            y: frame.maxY - notchInset / 2 - moreSize.height / 2,
            width: moreSize.width,
            height: moreSize.height
        )))

        let columnX = frame.minX + frame.width * rightColumnFraction
        let rowsTop = frame.maxY - notchInset - topInset
        let rowsHeight = labelRowHeight + titleRowHeight + detailRowHeight
        switch focus {
        case .event(joinable: true):
            let joinTop = rowsTop - rowsHeight - joinGap
            result.append((.join, CGRect(
                x: columnX + detailIndent,
                y: joinTop - joinSize.height,
                width: joinSize.width,
                height: joinSize.height
            )))
        case .nowPlaying:
            result.append((.openPlayer, CGRect(
                x: columnX,
                y: rowsTop - rowsHeight,
                width: frame.maxX - horizontalInset - columnX,
                height: rowsHeight
            )))
        case .event(joinable: false), .nothing:
            break
        }

        // The quick actions run right to left from the trailing inset, so the
        // Tray stays put as chips are added beside it.
        let barY = frame.minY + bottomInset
        var x = frame.maxX - horizontalInset
        for action in quickActions.reversed() {
            let width = chipWidth(action)
            x -= width
            result.append((action, CGRect(x: x, y: barY, width: width, height: barHeight)))
            x -= chipSpacing
        }
        return result
    }

    /// The action under a point, or `nil` for a miss (a few points of slop).
    public static func action(at point: CGPoint, in frame: CGRect, notchInset: CGFloat, focus: DashboardFocus) -> DashboardAction? {
        actions(in: frame, notchInset: notchInset, focus: focus)
            .first { $0.rect.insetBy(dx: -3, dy: -3).contains(point) }?
            .action
    }
}

// MARK: - Lid chip

/// The lid chip on the quick-action bar: Settings → Lid Closed's "Keep
/// working with the lid closed" switch, one click from the dashboard.
///
/// A view of `LidSettingsModel`, as the page is, so the chip and the page
/// cannot disagree; a click is the page's own tap on the switch.
public enum DashboardLidChip: Equatable, Sendable {
    /// The switch is off and a closed lid sleeps the Mac: a plain glyph,
    /// like any idle chip.
    case off
    /// On, and NotchHub is keeping the Mac awake with the lid closed
    /// (`LidAwakeEngine.isKeepingAwake` — the page's `.awake`, or its
    /// `.stillOff` with the switch on): the accent glyph of a running chip.
    case awake
    /// A plain glyph with a small accent dot: not what the switch alone
    /// says. Mostly "on, waiting" — on but not keeping the Mac awake for now:
    /// a guard holds (on battery, the apps closed…), it needs the password,
    /// the helper isn't working, or a change is on its way. Also the switch
    /// off while a closed lid still won't sleep the Mac — NotchHub's
    /// SleepDisabled 1 that could not be put back (`.stillOff`, e.g. the
    /// dialog cancelled) or one set outside NotchHub (`.outside`) — so the
    /// chip never looks idle then; Settings has Restore normal sleep….
    /// Not dimmed: a dim chip on this bar means a feature switched off in
    /// Settings.
    case waiting

    public init(_ lid: LidSettingsModel) {
        switch lid.status {
        case .awake, .stillOff:
            self = lid.switchOn ? .awake : .waiting
        case .outside:
            self = .waiting
        case .notManaged, .normal, .switching, .held, .needsYou:
            self = lid.switchOn ? .waiting : .off
        }
    }

    /// What a click asks for: the Settings switch's own tap — whatever the
    /// chip shows, the dot with the switch off included — or `nil` when the
    /// switch could not take it either (a change in flight, a launch that
    /// doesn't manage the Mac's sleep).
    public static func click(_ lid: LidSettingsModel) -> LidIntent? {
        let intent = LidIntent.setEnabled(!lid.switchOn)
        return lid.isEnabled(intent) ? intent : nil
    }
}
