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
}
