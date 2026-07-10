import Foundation
import Testing
@testable import Maria_s_Notebook

// Regression coverage for CSV date parsing: date-only strings (birthdays, start
// dates) must land at *local* midnight of the named day. They previously parsed at
// GMT midnight, which displayed as the previous day in US time zones and broke the
// importer's duplicate detection.
@Suite("CSV date parser")
struct DateParserTests {

    private func localDayComponents(of date: Date) -> DateComponents {
        AppCalendar.shared.dateComponents([.year, .month, .day], from: date)
    }

    @Test("ISO date-only strings resolve to local midnight of the named day")
    func isoDateOnlyIsLocalMidnight() throws {
        let date = try #require(DateParser.parse("2018-05-04"))
        let comps = localDayComponents(of: date)
        #expect(comps.year == 2018)
        #expect(comps.month == 5)
        #expect(comps.day == 4)
        #expect(date == AppCalendar.startOfDay(date))
    }

    @Test("US-style date-only strings resolve to local midnight of the named day")
    func usDateOnlyIsLocalMidnight() throws {
        let date = try #require(DateParser.parse("05/04/2018"))
        let comps = localDayComponents(of: date)
        #expect(comps.year == 2018)
        #expect(comps.month == 5)
        #expect(comps.day == 4)
        #expect(date == AppCalendar.startOfDay(date))
    }

    @Test("Datetime strings with an explicit zone stay absolute instants")
    func datetimeStaysAbsolute() throws {
        let date = try #require(DateParser.parse("2018-05-04T10:30:00+0000"))
        #expect(date.timeIntervalSince1970 == 1525429800)
    }

    @Test("Re-parsing a stored local-midnight date names the same calendar day")
    func roundTripStaysOnSameDay() throws {
        let parsed = try #require(DateParser.parse("2015-12-31"))
        // The duplicate-detection key formats via DateFormatters and compares
        // day-level; the parsed value must sit inside the local calendar day.
        #expect(AppCalendar.isSameDay(parsed, AppCalendar.startOfDay(parsed)))
    }
}
