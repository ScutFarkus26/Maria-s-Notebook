import Foundation
import Testing
@testable import CosmicDaybook

// The roster card, the list row, the birthday sort and the table countdown
// all count to one date. These pin the 29 February rule: 1 March in a
// common year, the day itself in a leap year.
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

    @Test("A leap-day birthday counts on 1 March in a common year")
    func leapDayMovesToMarchInCommonYear() {
        let birthday = day(2016, 2, 29)
        let today = day(2026, 9, 22)
        #expect(RosterBirthday.nextOccurrence(of: birthday, using: calendar, today: today) == day(2027, 3, 1))
        #expect(AgeUtils.nextBirthday(for: birthday, today: today, calendar: calendar) == day(2027, 3, 1))
    }

    @Test("A leap-day birthday counts on 29 February in a leap year")
    func leapDayKeepsItsDayInLeapYear() {
        let birthday = day(2016, 2, 29)
        let today = day(2027, 9, 22)
        #expect(RosterBirthday.nextOccurrence(of: birthday, using: calendar, today: today) == day(2028, 2, 29))
    }

    @Test("On 28 February of a common year, a leap-day child's birthday is tomorrow")
    func leapDayCountdownIsTomorrowOnTheTwentyEighth() {
        let birthday = day(2016, 2, 29)
        let today = day(2027, 2, 28)
        #expect(AgeUtils.daysUntilNextBirthday(for: birthday, today: today, calendar: calendar) == 1)
        #expect(RosterBirthday.nextOccurrence(of: birthday, using: calendar, today: today) == day(2027, 3, 1))
    }

    @Test("On 1 March of a common year, a leap-day child's birthday is today")
    func leapDayCountdownIsTodayOnTheFirstOfMarch() {
        let birthday = day(2016, 2, 29)
        let today = day(2027, 3, 1)
        #expect(AgeUtils.daysUntilNextBirthday(for: birthday, today: today, calendar: calendar) == 0)
    }

    @Test("No birthday on file counts from today")
    func missingBirthdayCountsFromToday() {
        let today = day(2026, 9, 22)
        #expect(RosterBirthday.nextOccurrence(of: nil, using: calendar, today: today) == today)
    }
}
