import Foundation
import Testing
@testable import CosmicDaybook

// The roster card, the list row, the birthday sort and the table countdown
// all count to one date. These pin the 29 February rule: 28 February in a
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

    @Test("A leap-day birthday counts on 28 February in a common year")
    func leapDayFallsBackInCommonYear() {
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

    @Test("On 28 February of a common year, a leap-day child's countdown is today")
    func leapDayCountdownIsTodayOnTheTwentyEighth() {
        let birthday = day(2016, 2, 29)
        let today = day(2027, 2, 28)
        #expect(AgeUtils.daysUntilNextBirthday(for: birthday, today: today, calendar: calendar) == 0)
        #expect(RosterBirthday.nextOccurrence(of: birthday, using: calendar, today: today) == today)
    }

    @Test("No birthday on file counts from today")
    func missingBirthdayCountsFromToday() {
        let today = day(2026, 9, 22)
        #expect(RosterBirthday.nextOccurrence(of: nil, using: calendar, today: today) == today)
    }
}
