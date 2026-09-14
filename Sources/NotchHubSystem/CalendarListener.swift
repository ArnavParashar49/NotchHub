import EventKit
import Foundation
import NotchHubCore

/// Observes the user's calendar and reports the next event.
///
/// Emits `calendarNext` on a refresh schedule (with any video-call link found
/// on the event, for the dashboard's Join button) and `calendarStarting` when
/// an event is about to begin. Requires calendar permission; if it is denied or
/// restricted the listener stays silent rather than fabricate events.
public final class CalendarListener: SystemListener {

    private let emit: (SystemEvent) -> Void
    private let store = EKEventStore()
    private var timer: Timer?
    private var hasAccess = false
    private var lastWarn: (title: String, inMinutes: Int)?

    public init(emit: @escaping (SystemEvent) -> Void) {
        self.emit = emit
    }

    public func start() {
        guard timer == nil else { return }
        requestAccess()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func requestAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized:
            hasAccess = true
        case .notDetermined:
            // Requesting without the usage-description string in Info.plist
            // makes macOS terminate the app, so check before asking.
            let handler: EKEventStoreRequestAccessCompletionHandler = { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.hasAccess = granted
                    if granted { self?.refresh() }
                }
            }
            if #available(macOS 14.0, *) {
                guard Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil else { return }
                store.requestFullAccessToEvents(completion: handler)
            } else {
                guard Bundle.main.object(forInfoDictionaryKey: "NSCalendarsUsageDescription") != nil else { return }
                store.requestAccess(to: .event, completion: handler)
            }
        default:
            // Denied or restricted: stay silent.
            hasAccess = false
        }
    }

    /// Looks ahead ~12 hours for the next event and emits the relevant facts.
    private func refresh() {
        guard hasAccess else { return }
        let now = Date()
        let horizon = now.addingTimeInterval(12 * 3600)
        let predicate = store.predicateForEvents(withStart: now, end: horizon, calendars: nil)
        let next = store.events(matching: predicate)
            .filter { $0.endDate >= now && !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .first

        guard let next else {
            emit(SystemEvent(source: .calendar, payload: .calendarNext(nil)))
            return
        }

        let title = next.title ?? "Event"
        emit(SystemEvent(source: .calendar, payload: .calendarNext(UpcomingEvent(
            title: title,
            startsAt: next.startDate,
            joinURL: MeetingLink.find(in: [next.url?.absoluteString, next.location, next.notes])
        ))))

        // Surface an imminent event once, not on every tick.
        let minutesUntil = Int((next.startDate.timeIntervalSince(now) / 60).rounded())
        if minutesUntil <= 5, minutesUntil >= 0 {
            if lastWarn?.title != title || lastWarn?.inMinutes != minutesUntil {
                lastWarn = (title, minutesUntil)
                emit(SystemEvent(source: .calendar, payload: .calendarStarting(
                    title: title, inMinutes: minutesUntil
                )))
            }
        }
    }
}
