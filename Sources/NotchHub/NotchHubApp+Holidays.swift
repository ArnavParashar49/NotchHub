import AppKit
import NotchHubCore
import SwiftUI

/// Holidays: the pet dresses for them (when its hat is seasonal) and says so —
/// in its panel's title, and once a day in the island. Computed from the date
/// (`PetHolidays`); nothing polls: one task waits for the next midnight.
extension NotchHubApp {

    private static let greetedKey = "NotchHub.petHolidayGreeted"

    /// Today's holiday, when the pet is shown with Holidays on; worked out once
    /// a day.
    func todaysHoliday(now: Date = Date()) -> PetHoliday? {
        guard petVisible, petSettings.holidays else { return nil }
        let key = Self.dayKey(now)
        if let cache = holidayCache, cache.day == key {
            return cache.holiday
        }
        let holiday = PetHolidays.holiday(on: now)
        holidayCache = (key, holiday)
        return holiday
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// Greets today's holiday once the listeners have settled, then again each
    /// midnight a holiday begins.
    func scheduleHolidayGreeting() {
        holidayTask?.cancel()
        holidayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.monitorSettlePeriod + 2) * 1_000_000_000))
            while !Task.isCancelled {
                guard let delay = self?.greetHolidayAndWaitTime() else { return }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// Greets today's holiday if it hasn't been; returns how long until the
    /// next day starts.
    private func greetHolidayAndWaitTime() -> TimeInterval {
        greetHolidayIfDue()
        let now = Date()
        let next = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .nextTime)
        return max(60, (next ?? now.addingTimeInterval(3600)).timeIntervalSince(now))
    }

    /// Shows "Happy Diwali!" (or the day's greeting) in the island once a day,
    /// and the pet celebrates.
    func greetHolidayIfDue() {
        holidayCache = nil
        guard let holiday = todaysHoliday() else { return }
        let key = Self.dayKey(Date()) + ":" + holiday.id
        guard UserDefaults.standard.string(forKey: Self.greetedKey) != key else { return }
        UserDefaults.standard.set(key, forKey: Self.greetedKey)
        queue.focusTemporarily(Activity(kind: .custom, title: holiday.greeting, symbol: holiday.symbol, autoDismiss: 5))
        if petSettings.reactions {
            petBrain.handle(.holiday, context: petContext(), now: Date())
        }
        log("pet: \(holiday.greeting)")
        renderQueue()
    }
}
