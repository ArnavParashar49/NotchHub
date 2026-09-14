import Foundation

/// A day the pet marks: it says so, and may dress for it.
public struct PetHoliday: Equatable, Sendable {
    public let id: String
    /// What the pet says ("Happy Diwali!").
    public let greeting: String
    /// What it wears for the day, if anything.
    public let hat: PetHat?
    /// An SF Symbol for the island's greeting.
    public let symbol: String
}

/// The major holidays the pet knows, each computed from its own calendar:
/// Gregorian dates, Easter's computus, nth weekdays, and the Chinese
/// lunisolar, Islamic (Umm al-Qura) and Hebrew calendars. Diwali and Holi
/// follow the Hindu lunisolar calendar, which Foundation cannot compute, so
/// they come from tables of published dates (extend them as years pass).
///
/// Religious observances get a greeting; the pet only dresses up for the
/// festive ones.
public enum PetHolidays {

    public static let christmas = PetHoliday(id: "christmas", greeting: "Merry Christmas!", hat: .santa, symbol: "gift.fill")
    public static let newYear = PetHoliday(id: "new-year", greeting: "Happy New Year!", hat: .party, symbol: "party.popper.fill")
    public static let lunarNewYear = PetHoliday(id: "lunar-new-year", greeting: "Happy Lunar New Year!", hat: .lunar, symbol: "sparkles")
    public static let eidAlFitr = PetHoliday(id: "eid-al-fitr", greeting: "Eid Mubarak!", hat: nil, symbol: "moon.stars.fill")
    public static let eidAlAdha = PetHoliday(id: "eid-al-adha", greeting: "Eid Mubarak!", hat: nil, symbol: "moon.stars.fill")
    public static let diwali = PetHoliday(id: "diwali", greeting: "Happy Diwali!", hat: .marigold, symbol: "flame.fill")
    public static let hanukkah = PetHoliday(id: "hanukkah", greeting: "Happy Hanukkah!", hat: nil, symbol: "sparkles")
    public static let holi = PetHoliday(id: "holi", greeting: "Happy Holi!", hat: nil, symbol: "paintpalette.fill")
    public static let easter = PetHoliday(id: "easter", greeting: "Happy Easter!", hat: .bunny, symbol: "hare.fill")
    public static let thanksgiving = PetHoliday(id: "thanksgiving", greeting: "Happy Thanksgiving!", hat: .turkey, symbol: "fork.knife")
    public static let halloween = PetHoliday(id: "halloween", greeting: "Happy Halloween!", hat: .witch, symbol: "moon.stars.fill")
    public static let diaDeMuertos = PetHoliday(id: "dia-de-muertos", greeting: "Feliz Día de Muertos!", hat: .marigold, symbol: "sparkles")
    public static let roshHashanah = PetHoliday(id: "rosh-hashanah", greeting: "Shana Tova!", hat: nil, symbol: "sparkles")
    public static let ramadan = PetHoliday(id: "ramadan", greeting: "Ramadan Mubarak!", hat: nil, symbol: "moon.stars.fill")
    public static let midAutumn = PetHoliday(id: "mid-autumn", greeting: "Happy Mid-Autumn Festival!", hat: nil, symbol: "moon.fill")
    public static let valentines = PetHoliday(id: "valentines", greeting: "Happy Valentine's Day!", hat: .hearts, symbol: "heart.fill")
    public static let stPatricks = PetHoliday(id: "st-patricks", greeting: "Happy St. Patrick's Day!", hat: .shamrock, symbol: "leaf.fill")
    public static let nowruz = PetHoliday(id: "nowruz", greeting: "Happy Nowruz!", hat: nil, symbol: "leaf.fill")

    /// Lakshmi Puja, Diwali's main day: [year: [month, day]].
    static let diwaliDates: [Int: [Int]] = [
        2026: [11, 8], 2027: [10, 29], 2028: [10, 17], 2029: [11, 5], 2030: [10, 26],
        2031: [11, 14], 2032: [11, 2], 2033: [10, 22], 2034: [11, 10],
    ]

    /// Holi (Rangwali Holi, the day of colours): [year: [month, day]].
    static let holiDates: [Int: [Int]] = [
        2026: [3, 3], 2027: [3, 22], 2028: [3, 11], 2029: [2, 28], 2030: [3, 20], 2031: [3, 9],
    ]

    /// The holiday `date` falls on in `calendar`'s time zone, or `nil`. Where two
    /// meet, the first in `all(on:)` wins.
    public static func holiday(on date: Date, calendar: Calendar = .current, region: String? = Locale.current.region?.identifier) -> PetHoliday? {
        all(on: date, calendar: calendar, region: region).first
    }

    /// Every holiday on `date`, most important first.
    public static func all(on date: Date, calendar: Calendar = .current, region: String? = Locale.current.region?.identifier) -> [PetHoliday] {
        let day = Day(date: date, calendar: calendar)
        var found: [PetHoliday] = []
        if day.month == 12, (24...26).contains(day.day) { found.append(christmas) }
        if (day.month == 12 && day.day == 31) || (day.month == 1 && day.day == 1) { found.append(newYear) }
        let chinese = day.components(in: .chinese)
        if !chinese.leap, chinese.month == 1, chinese.day <= 2 { found.append(lunarNewYear) }
        let islamic = day.components(in: .islamicUmmAlQura)
        if islamic.month == 10, islamic.day <= 3 { found.append(eidAlFitr) }
        if islamic.month == 12, (10...12).contains(islamic.day) { found.append(eidAlAdha) }
        if day.isWithin(diwaliDates[day.year], before: 1, after: 1) { found.append(diwali) }
        if (0...7).contains(where: { day.shifted(-$0).components(in: .hebrew).matches(month: 3, day: 25) }) { found.append(hanukkah) }
        if day.isWithin(holiDates[day.year], before: 0, after: 1) { found.append(holi) }
        let easterDate = easter(year: day.year)
        if day.month == easterDate.month, day.day == easterDate.day { found.append(easter) }
        if region == "CA" ? day.isNthWeekday(2, weekday: 2, month: 10) : day.isNthWeekday(4, weekday: 5, month: 11) {
            found.append(thanksgiving)
        }
        if day.month == 10, day.day == 31 { found.append(halloween) }
        if day.month == 11, day.day <= 2 { found.append(diaDeMuertos) }
        let hebrew = day.components(in: .hebrew)
        if hebrew.month == 1, hebrew.day <= 2 { found.append(roshHashanah) }
        if islamic.month == 9, islamic.day == 1 { found.append(ramadan) }
        if !chinese.leap, chinese.month == 8, chinese.day == 15 { found.append(midAutumn) }
        if day.month == 2, day.day == 14 { found.append(valentines) }
        if day.month == 3, day.day == 17 { found.append(stPatricks) }
        if day.month == 3, (20...21).contains(day.day) { found.append(nowruz) }
        return found
    }

    /// Western Easter Sunday (the anonymous Gregorian computus).
    public static func easter(year: Int) -> (month: Int, day: Int) {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let n = h + l - 7 * m + 114
        return (n / 31, n % 31 + 1)
    }

    /// A day, as seen by a calendar.
    struct Day {
        let date: Date
        let calendar: Calendar
        let year: Int
        let month: Int
        let day: Int

        init(date: Date, calendar: Calendar) {
            self.date = date
            self.calendar = calendar
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            year = parts.year ?? 0
            month = parts.month ?? 0
            day = parts.day ?? 0
        }

        struct Lunar {
            let month: Int
            let day: Int
            let leap: Bool

            func matches(month: Int, day: Int) -> Bool {
                !leap && self.month == month && self.day == day
            }
        }

        /// The same instant in another calendar (same time zone).
        func components(in identifier: Calendar.Identifier) -> Lunar {
            var other = Calendar(identifier: identifier)
            other.timeZone = calendar.timeZone
            let parts = other.dateComponents([.month, .day], from: date)
            return Lunar(month: parts.month ?? 0, day: parts.day ?? 0, leap: parts.isLeapMonth ?? false)
        }

        func shifted(_ days: Int) -> Day {
            Day(date: calendar.date(byAdding: .day, value: days, to: date) ?? date, calendar: calendar)
        }

        /// Whether this is the nth `weekday` (1 = Sunday) of `month`.
        func isNthWeekday(_ n: Int, weekday: Int, month: Int) -> Bool {
            self.month == month && calendar.component(.weekday, from: date) == weekday && (day - 1) / 7 == n - 1
        }

        /// Whether this day is within `before`…`after` days of a [month, day].
        func isWithin(_ monthDay: [Int]?, before: Int, after: Int) -> Bool {
            guard let monthDay, monthDay.count == 2,
                  let target = calendar.date(from: DateComponents(year: year, month: monthDay[0], day: monthDay[1])) else { return false }
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: target), to: calendar.startOfDay(for: date)).day ?? .max
            return (-before...after).contains(offset)
        }
    }
}
