import Foundation
import Testing
@testable import CosmicDaybook

// The roster card and the list row count to one date (`RosterBirthday`):
// a 29 February birthday falls on 28 February in a common year, as on the
// attendance tile, and on the day itself in a leap year. `AgeUtils`, which
// the birthday sort and the table countdown read, agrees.
@Suite("Roster birthday")
struct RosterBirthdayTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("A leap-day birthday counts on 28 February on the roster and in AgeUtils, in a common year")
    func leapDayInCommonYear() {
        let birthday = day(2016, 2, 29)
        let today = day(2026, 9, 22)
        #expect(RosterBirthday.nextOccurrence(of: birthday, using: calendar, today: today) == day(2027, 2, 28))
        #expect(AgeUtils.nextBirthday(for: birthday, today: today, calendar: calendar) == day(2027, 2, 28))
    }

    @Test("A leap-day birthday counts on 29 February in a leap year")
    func leapDayKeepsItsDayInLeapYear() {
        let birthday = day(2016, 2, 29)
        let today = day(2027, 9, 22)
        #expect(RosterBirthday.nextOccurrence(of: birthday, using: calendar, today: today) == day(2028, 2, 29))
    }

    @Test("On 28 February of a common year, a leap-day child's birthday is today, in AgeUtils and on the roster")
    func leapDayCountdownIsTodayOnTheTwentyEighth() {
        let birthday = day(2016, 2, 29)
        let today = day(2027, 2, 28)
        #expect(AgeUtils.daysUntilNextBirthday(for: birthday, today: today, calendar: calendar) == 0)
        #expect(RosterBirthday.nextOccurrence(of: birthday, using: calendar, today: today) == today)
    }

    @Test("On 1 March of a common year, a leap-day child's birthday has passed until next year's 29 February")
    func leapDayCountdownOnTheFirstOfMarch() {
        let birthday = day(2016, 2, 29)
        let today = day(2027, 3, 1)
        #expect(AgeUtils.nextBirthday(for: birthday, today: today, calendar: calendar) == day(2028, 2, 29))
    }

    @Test("No birthday on file counts from today")
    func missingBirthdayCountsFromToday() {
        let today = day(2026, 9, 22)
        #expect(RosterBirthday.nextOccurrence(of: nil, using: calendar, today: today) == today)
    }

    // MARK: - Hebrew birthday

    // Hebcal: 2024-03-24 = 14 Adar II 5784 (Purim); 2024-03-23 = 13 Adar II 5784;
    // 14 Adar II 5787 = 2027-03-23.

    @Test("A Hebrew birthday today counts as today, and born after sunset takes the next day's date")
    func hebrewBirthdayToday() {
        let today = day(2027, 3, 23)
        let born = day(2024, 3, 24)
        #expect(RosterBirthday.nextHebrewOccurrence(of: born, bornAfterSunset: false, using: calendar, today: today)
            == today)
        #expect(RosterSignalRules.daysUntilSoonHebrewBirthday(
            born, bornAfterSunset: false, calendar: calendar, today: today
        ) == 0)
        // Born the evening before: the same Hebrew date.
        #expect(RosterSignalRules.daysUntilSoonHebrewBirthday(
            day(2024, 3, 23), bornAfterSunset: true, calendar: calendar, today: today
        ) == 0)
        // Born that day in daylight: 13 Adar II, a day earlier, already past.
        #expect(RosterSignalRules.daysUntilSoonHebrewBirthday(
            day(2024, 3, 23), bornAfterSunset: false, calendar: calendar, today: today
        ) == nil)
    }

    @Test("A Hebrew birthday on the window's last day counts; the day after doesn't")
    func hebrewBirthdayOnTheWindowsLastDay() {
        let born = day(2024, 3, 24)
        #expect(RosterSignalRules.birthdaySoonDays == 6)
        #expect(RosterSignalRules.daysUntilSoonHebrewBirthday(
            born, bornAfterSunset: false, calendar: calendar, today: day(2027, 3, 17)
        ) == 6)
        #expect(RosterSignalRules.daysUntilSoonHebrewBirthday(
            born, bornAfterSunset: false, calendar: calendar, today: day(2027, 3, 16)
        ) == nil)
    }

    @Test("No birthday on file has no Hebrew birthday")
    func missingBirthdayHasNoHebrewBirthday() {
        let today = day(2026, 9, 22)
        #expect(RosterBirthday.nextHebrewOccurrence(of: nil, bornAfterSunset: true, using: calendar, today: today)
            == nil)
        #expect(RosterSignalRules.daysUntilSoonHebrewBirthday(
            nil, bornAfterSunset: false, calendar: calendar, today: today
        ) == nil)
    }
}
