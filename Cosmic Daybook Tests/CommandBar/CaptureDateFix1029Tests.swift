import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-29, #19: a weekday anywhere in a capture became the day
/// the lesson was given ("her Tuesday work plan"), and "next Tuesday" was read
/// as last Tuesday. Only a weekday said as the date counts now, and one still
/// to come is passed over, since the day is when the lesson was given.
@Suite("Capture date: weekdays said as the date (fix 10-29 #19)")
struct CaptureDateFix1029Tests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

    /// Thursday, October 29, 2026, mid-morning.
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 10)) ?? Date()
    }

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day)) ?? Date()
    }

    private func parsed(_ text: String) -> Date {
        CaptureDateParser.day(in: text, today: today, calendar: calendar)
    }

    @Test("A weekday said as the date names that day")
    func weekdayAsDate() {
        #expect(parsed("On Tuesday I showed Leah the map") == day(10, 27))
        #expect(parsed("Tuesday I showed Leah the map") == day(10, 27))
        #expect(parsed("Tuesday morning I showed Leah the map") == day(10, 27))
        #expect(parsed("I showed Leah the map Tuesday.") == day(10, 27))
        #expect(parsed("I showed Leah the map Tuesday afternoon, and she loved it") == day(10, 27))
        #expect(parsed("Last Thursday I gave Maya the cube") == day(10, 22))
        #expect(parsed("This past Monday I gave Maya the cube") == day(10, 26))
        #expect(parsed("This Tuesday I gave Maya the cube") == day(10, 27))
    }

    @Test("A weekday that describes something else names no day")
    func weekdayAsDescription() {
        #expect(parsed("Maya finished her Tuesday work plan") == day(10, 29))
        #expect(parsed("We went over Monday's spelling words") == day(10, 29))
        #expect(parsed("Monday's spelling words were hard for Ari") == day(10, 29))
        #expect(parsed("Maya should finish the map by Friday.") == day(10, 29))
        #expect(parsed("Ari waters the plants every Monday.") == day(10, 29))
    }

    @Test("Next Tuesday is still to come, so it isn't the day the lesson was given")
    func nextWeekdayIsAhead() {
        #expect(parsed("Next Tuesday I'll show Maya the cube") == day(10, 29))
        #expect(parsed("I gave Maya the cube, and we go on next Tuesday.") == day(10, 29))
        #expect(parsed("This Saturday we'll practice the cube") == day(10, 29))
        // A day she names after it still counts.
        #expect(parsed("Next Tuesday we go on; yesterday I gave Maya the cube") == day(10, 28))
    }
}
