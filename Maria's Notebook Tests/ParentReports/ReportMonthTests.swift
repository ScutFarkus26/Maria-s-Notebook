// ReportMonthTests.swift
// Month windowing for the parent report cycle: key round-trips, calendar
// boundaries (year wrap, leap February, DST), and the due-window math.

import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Report Month")
struct ReportMonthTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    @Test("monthKey formats and parses round-trip")
    func monthKeyRoundTrip() {
        let month = ReportMonth(year: 2026, month: 9)
        #expect(month.monthKey == "2026-09")
        #expect(ReportMonth.parse(monthKey: "2026-09") == month)
        #expect(ReportMonth.parse(monthKey: "2026-13") == nil)
        #expect(ReportMonth.parse(monthKey: "garbage") == nil)
        #expect(ReportMonth.parse(monthKey: "2026") == nil)
    }

    @Test("previous/next wrap across the year boundary")
    func yearWrap() {
        #expect(ReportMonth(year: 2026, month: 1).previous == ReportMonth(year: 2025, month: 12))
        #expect(ReportMonth(year: 2026, month: 12).next == ReportMonth(year: 2027, month: 1))
    }

    @Test("Leap February interval covers exactly 29 days")
    func leapFebruary() {
        let interval = ReportMonth(year: 2028, month: 2).dateInterval(calendar: calendar)
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day
        #expect(days == 29)
    }

    @Test("DST month interval starts and ends on the 1st at local midnight")
    func dstMonthBoundaries() {
        // March 2026 contains a DST spring-forward in America/New_York.
        let interval = ReportMonth(year: 2026, month: 3).dateInterval(calendar: calendar)
        #expect(calendar.component(.day, from: interval.start) == 1)
        #expect(calendar.component(.month, from: interval.start) == 3)
        #expect(calendar.component(.day, from: interval.end) == 1)
        #expect(calendar.component(.month, from: interval.end) == 4)
    }

    @Test("closedRange upper bound stays inside the month")
    func closedRangeStaysInMonth() {
        let month = ReportMonth(year: 2026, month: 9)
        let range = month.closedRange(calendar: calendar)
        #expect(calendar.component(.month, from: range.upperBound) == 9)
        #expect(range.contains(date(2026, 9, 30, hour: 23)))
        #expect(!range.contains(date(2026, 10, 1, hour: 0)))
    }

    @Test("containing and currentCycle pick the right months")
    func containingAndCurrentCycle() {
        #expect(ReportMonth.containing(date(2026, 8, 21), calendar: calendar) == ReportMonth(year: 2026, month: 8))
        // Mid-month: the open cycle is always last month's records.
        #expect(ReportMonth.currentCycle(now: date(2026, 8, 21), calendar: calendar) == ReportMonth(year: 2026, month: 7))
        // January reports on December of the prior year.
        #expect(ReportMonth.currentCycle(now: date(2027, 1, 3), calendar: calendar) == ReportMonth(year: 2026, month: 12))
    }

    @Test("cycleWindow opens on the 1st of the next month and closes after day 7")
    func cycleWindow() {
        let september = ReportMonth(year: 2026, month: 9)
        let window = september.cycleWindow(calendar: calendar)
        #expect(window.start == ReportMonth(year: 2026, month: 10).dateInterval(calendar: calendar).start)
        #expect(window.contains(date(2026, 10, 1)))
        #expect(window.contains(date(2026, 10, 7)))
        #expect(!window.contains(date(2026, 10, 9)))
    }
}
