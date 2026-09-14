import Foundation
import Testing
@testable import NotchHubCore

@Suite("Pet holidays")
struct PetHolidayTests {

    func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func holiday(_ year: Int, _ month: Int, _ day: Int, region: String? = "US") -> PetHoliday? {
        let calendar = calendar()
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return PetHolidays.holiday(on: date, calendar: calendar, region: region)
    }

    @Test("fixed-date holidays")
    func fixed() {
        #expect(holiday(2026, 12, 25)?.id == "christmas")
        #expect(holiday(2026, 12, 31)?.id == "new-year")
        #expect(holiday(2027, 1, 1)?.id == "new-year")
        #expect(holiday(2026, 2, 14)?.id == "valentines")
        #expect(holiday(2026, 3, 17)?.id == "st-patricks")
        #expect(holiday(2026, 10, 31)?.id == "halloween")
        #expect(holiday(2026, 11, 2)?.id == "dia-de-muertos")
        // 2026's Nowruz falls inside Eid al-Fitr, which ranks higher; 2027's is clear.
        #expect(holiday(2027, 3, 21)?.id == "nowruz")
    }

    @Test("lunar calendars: Lunar New Year, Mid-Autumn, Ramadan, Eid, Rosh Hashanah, Hanukkah")
    func lunar() {
        #expect(holiday(2026, 2, 17)?.id == "lunar-new-year")
        #expect(holiday(2027, 2, 6)?.id == "lunar-new-year")
        #expect(holiday(2026, 9, 25)?.id == "mid-autumn")
        // 2026's first day of Ramadan is also Lunar New Year's second day, which ranks higher.
        #expect(holiday(2027, 2, 8)?.id == "ramadan")
        #expect(holiday(2026, 3, 20)?.id == "eid-al-fitr")
        #expect(holiday(2026, 5, 27)?.id == "eid-al-adha")
        #expect(holiday(2026, 9, 12)?.id == "rosh-hashanah")
        #expect(holiday(2026, 12, 5)?.id == "hanukkah")
        #expect(holiday(2026, 12, 12)?.id == "hanukkah")
        #expect(holiday(2026, 12, 13)?.id != "hanukkah")
    }

    @Test("Diwali and Holi from their published dates")
    func hindu() {
        #expect(holiday(2026, 11, 7)?.id == "diwali")
        #expect(holiday(2026, 11, 8)?.id == "diwali")
        #expect(holiday(2026, 11, 9)?.id == "diwali")
        #expect(holiday(2026, 11, 10) == nil)
        #expect(holiday(2027, 10, 29)?.id == "diwali")
        #expect(holiday(2026, 3, 3)?.id == "holi")
        #expect(holiday(2026, 3, 4)?.id == "holi")
    }

    @Test("Easter by computus, Thanksgiving by region")
    func computed() {
        for (year, month, day) in [(2025, 4, 20), (2026, 4, 5), (2027, 3, 28), (2028, 4, 16), (2030, 4, 21)] {
            let easter = PetHolidays.easter(year: year)
            #expect(easter.month == month && easter.day == day, "\(year)")
        }
        #expect(holiday(2026, 4, 5)?.id == "easter")
        #expect(holiday(2026, 11, 26, region: "US")?.id == "thanksgiving")
        #expect(holiday(2026, 11, 26, region: "IN")?.id == "thanksgiving")
        #expect(holiday(2026, 10, 12, region: "CA")?.id == "thanksgiving")
        #expect(holiday(2026, 11, 26, region: "CA") == nil)
        #expect(holiday(2026, 11, 19, region: "US") == nil)
    }

    @Test("an ordinary day is no holiday; overlaps pick the bigger one")
    func ordinaryAndOverlaps() {
        #expect(holiday(2026, 9, 14) == nil)
        #expect(holiday(2026, 6, 10) == nil)
        // Hanukkah 2027 overlaps Christmas.
        let calendar = calendar()
        let christmas2027 = calendar.date(from: DateComponents(year: 2027, month: 12, day: 25, hour: 12))!
        let all = PetHolidays.all(on: christmas2027, calendar: calendar, region: "US").map(\.id)
        #expect(all.first == "christmas")
        #expect(all.contains("hanukkah"))
    }

    @Test("a seasonal hat dresses for the holiday first, then the season; a chosen hat stays")
    func hats() {
        let calendar = calendar()
        let diwali = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))!
        let december = calendar.date(from: DateComponents(year: 2026, month: 12, day: 8, hour: 12))!
        #expect(PetHatChoice.seasonal.hat(on: diwali, calendar: calendar, holiday: PetHolidays.diwali) == .marigold)
        #expect(PetHatChoice.seasonal.hat(on: december, calendar: calendar, holiday: nil) == .santa)
        #expect(PetHatChoice.seasonal.hat(on: diwali, calendar: calendar, holiday: PetHolidays.hanukkah) == nil)
        #expect(PetHatChoice.bunny.hat(on: diwali, calendar: calendar, holiday: PetHolidays.diwali) == .bunny)
        #expect(PetHatChoice.none.hat(on: december, calendar: calendar, holiday: PetHolidays.christmas) == nil)
        for hat in PetHat.allCases {
            #expect(PetHatChoice(rawValue: hat.rawValue) != nil, "no choice for \(hat)")
        }
    }

    @Test("settings saved before Holidays existed turn it on")
    func settings() throws {
        let saved = #"{"showPet":true,"mischief":false}"#
        let settings = try JSONDecoder().decode(PetSettings.self, from: Data(saved.utf8))
        #expect(settings.holidays)
        #expect(!settings.mischief)
    }
}
