#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("DateCalculations Tests")
struct DateCalculationsTests {

    // MARK: - Test Helpers

    private func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components)!
    }

    // MARK: - adding Tests

    @Test("Adding days to a date")
    func addingDaysToDate() {
        let baseDate = date(year: 2025, month: 1, day: 15)

        let result = DateCalculations.adding(.day, value: 5, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.day, from: result) == 20)
    }

    @Test("Adding negative days to a date")
    func addingNegativeDays() {
        let baseDate = date(year: 2025, month: 1, day: 15)

        let result = DateCalculations.adding(.day, value: -5, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.day, from: result) == 10)
    }

    @Test("Adding months to a date")
    func addingMonthsToDate() {
        let baseDate = date(year: 2025, month: 1, day: 15)

        let result = DateCalculations.adding(.month, value: 3, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.month, from: result) == 4)
    }

    @Test("Adding years to a date")
    func addingYearsToDate() {
        let baseDate = date(year: 2025, month: 6, day: 15)

        let result = DateCalculations.adding(.year, value: 2, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.year, from: result) == 2027)
    }

    @Test("Adding zero returns same date")
    func addingZero() {
        let baseDate = date(year: 2025, month: 1, day: 15)

        let result = DateCalculations.adding(.day, value: 0, to: baseDate)

        #expect(result == baseDate)
    }

    // MARK: - addingDays Tests

    @Test("addingDays convenience adds days correctly")
    func addingDaysConvenience() {
        let baseDate = date(year: 2025, month: 1, day: 15)

        let result = DateCalculations.addingDays(10, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.day, from: result) == 25)
    }

    @Test("addingDays crosses month boundary")
    func addingDaysCrossesMonth() {
        let baseDate = date(year: 2025, month: 1, day: 30)

        let result = DateCalculations.addingDays(5, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.month, from: result) == 2)
        #expect(calendar.component(.day, from: result) == 4)
    }

    @Test("addingDays crosses year boundary")
    func addingDaysCrossesYear() {
        let baseDate = date(year: 2025, month: 12, day: 30)

        let result = DateCalculations.addingDays(5, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.year, from: result) == 2026)
        #expect(calendar.component(.month, from: result) == 1)
    }

    @Test("addingDays with negative value")
    func addingDaysNegative() {
        let baseDate = date(year: 2025, month: 1, day: 15)

        let result = DateCalculations.addingDays(-20, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.month, from: result) == 12)
        #expect(calendar.component(.year, from: result) == 2024)
    }

    // MARK: - addingHours Tests

    @Test("addingHours adds hours correctly")
    func addingHoursCorrectly() {
        let baseDate = date(year: 2025, month: 1, day: 15, hour: 10)

        let result = DateCalculations.addingHours(5, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.hour, from: result) == 15)
    }

    @Test("addingHours crosses day boundary")
    func addingHoursCrossesDay() {
        let baseDate = date(year: 2025, month: 1, day: 15, hour: 20)

        let result = DateCalculations.addingHours(8, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.day, from: result) == 16)
        #expect(calendar.component(.hour, from: result) == 4)
    }

    @Test("addingHours with negative value")
    func addingHoursNegative() {
        let baseDate = date(year: 2025, month: 1, day: 15, hour: 5)

        let result = DateCalculations.addingHours(-10, to: baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.day, from: result) == 14)
        #expect(calendar.component(.hour, from: result) == 19)
    }

    // MARK: - startOfDay Tests

    @Test("startOfDay returns midnight")
    func startOfDayReturnsMidnight() {
        let baseDate = date(year: 2025, month: 1, day: 15, hour: 14, minute: 30, second: 45)

        let result = DateCalculations.startOfDay(baseDate)

        let calendar = Calendar.current
        #expect(calendar.component(.year, from: result) == 2025)
        #expect(calendar.component(.month, from: result) == 1)
        #expect(calendar.component(.day, from: result) == 15)
        #expect(calendar.component(.hour, from: result) == 0)
        #expect(calendar.component(.minute, from: result) == 0)
        #expect(calendar.component(.second, from: result) == 0)
    }

    @Test("startOfDay is idempotent")
    func startOfDayIdempotent() {
        let baseDate = date(year: 2025, month: 1, day: 15, hour: 14)
        let firstCall = DateCalculations.startOfDay(baseDate)

        let secondCall = DateCalculations.startOfDay(firstCall)

        #expect(firstCall == secondCall)
    }
}

@Suite("Date+Normalization Tests")
struct DateNormalizationTests {

    // MARK: - Test Helpers

    private func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    // MARK: - startOfDay property Tests

    @Test("startOfDay property returns midnight")
    func startOfDayProperty() {
        let testDate = date(year: 2025, month: 6, day: 15, hour: 14, minute: 30)

        let result = testDate.startOfDay

        let calendar = Calendar.current
        #expect(calendar.component(.hour, from: result) == 0)
        #expect(calendar.component(.minute, from: result) == 0)
    }

    // MARK: - isSameDay Tests

    @Test("isSameDay returns true for same day different times")
    func sameDayDifferentTimes() {
        let date1 = date(year: 2025, month: 6, day: 15, hour: 9)
        let date2 = date(year: 2025, month: 6, day: 15, hour: 21)

        #expect(date1.isSameDay(as: date2) == true)
    }

    @Test("isSameDay returns false for different days")
    func differentDays() {
        let date1 = date(year: 2025, month: 6, day: 15)
        let date2 = date(year: 2025, month: 6, day: 16)

        #expect(date1.isSameDay(as: date2) == false)
    }

    @Test("isSameDay returns false for different months")
    func differentMonths() {
        let date1 = date(year: 2025, month: 6, day: 15)
        let date2 = date(year: 2025, month: 7, day: 15)

        #expect(date1.isSameDay(as: date2) == false)
    }

    @Test("isSameDay returns false for different years")
    func differentYears() {
        let date1 = date(year: 2025, month: 6, day: 15)
        let date2 = date(year: 2026, month: 6, day: 15)

        #expect(date1.isSameDay(as: date2) == false)
    }

    // MARK: - isBeforeDay Tests

    @Test("isBeforeDay returns true when before")
    func isBeforeDayTrue() {
        let date1 = date(year: 2025, month: 6, day: 14)
        let date2 = date(year: 2025, month: 6, day: 15)

        #expect(date1.isBeforeDay(date2) == true)
    }

    @Test("isBeforeDay returns false when after")
    func isBeforeDayFalseWhenAfter() {
        let date1 = date(year: 2025, month: 6, day: 16)
        let date2 = date(year: 2025, month: 6, day: 15)

        #expect(date1.isBeforeDay(date2) == false)
    }

    @Test("isBeforeDay returns false for same day")
    func isBeforeDayFalseSameDay() {
        let date1 = date(year: 2025, month: 6, day: 15, hour: 9)
        let date2 = date(year: 2025, month: 6, day: 15, hour: 21)

        #expect(date1.isBeforeDay(date2) == false)
    }

    // MARK: - isAfterDay Tests

    @Test("isAfterDay returns true when after")
    func isAfterDayTrue() {
        let date1 = date(year: 2025, month: 6, day: 16)
        let date2 = date(year: 2025, month: 6, day: 15)

        #expect(date1.isAfterDay(date2) == true)
    }

    @Test("isAfterDay returns false when before")
    func isAfterDayFalseWhenBefore() {
        let date1 = date(year: 2025, month: 6, day: 14)
        let date2 = date(year: 2025, month: 6, day: 15)

        #expect(date1.isAfterDay(date2) == false)
    }

    @Test("isAfterDay returns false for same day")
    func isAfterDayFalseSameDay() {
        let date1 = date(year: 2025, month: 6, day: 15, hour: 21)
        let date2 = date(year: 2025, month: 6, day: 15, hour: 9)

        #expect(date1.isAfterDay(date2) == false)
    }
}

@Suite("AppCalendar Tests")
struct AppCalendarTests {

    // MARK: - Test Helpers

    private func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    // MARK: - startOfDay Tests

    @Test("AppCalendar.startOfDay returns midnight")
    func startOfDayMidnight() {
        let testDate = date(year: 2025, month: 6, day: 15, hour: 14, minute: 30)

        let result = AppCalendar.startOfDay(testDate)

        let calendar = Calendar.current
        #expect(calendar.component(.hour, from: result) == 0)
        #expect(calendar.component(.minute, from: result) == 0)
        #expect(calendar.component(.second, from: result) == 0)
    }

    // MARK: - dayRange Tests

    @Test("AppCalendar.dayRange returns correct range")
    func dayRangeCorrect() {
        let testDate = date(year: 2025, month: 6, day: 15, hour: 14)

        let range = AppCalendar.dayRange(for: testDate)

        let calendar = Calendar.current
        #expect(calendar.component(.day, from: range.start) == 15)
        #expect(calendar.component(.day, from: range.end) == 16)
    }

    @Test("AppCalendar.dayRange end is exclusive")
    func dayRangeEndExclusive() {
        let testDate = date(year: 2025, month: 6, day: 15)

        let range = AppCalendar.dayRange(for: testDate)

        // End should be start of next day
        let calendar = Calendar.current
        #expect(calendar.component(.hour, from: range.end) == 0)
        #expect(calendar.component(.minute, from: range.end) == 0)
    }

    // MARK: - isSameDay Tests

    @Test("AppCalendar.isSameDay returns true for same day")
    func isSameDayTrue() {
        let date1 = date(year: 2025, month: 6, day: 15, hour: 9)
        let date2 = date(year: 2025, month: 6, day: 15, hour: 21)

        #expect(AppCalendar.isSameDay(date1, date2) == true)
    }

    @Test("AppCalendar.isSameDay returns false for different days")
    func isSameDayFalse() {
        let date1 = date(year: 2025, month: 6, day: 15)
        let date2 = date(year: 2025, month: 6, day: 16)

        #expect(AppCalendar.isSameDay(date1, date2) == false)
    }

    // MARK: - addingDays Tests

    @Test("AppCalendar.addingDays adds days correctly")
    func addingDaysCorrect() {
        let testDate = date(year: 2025, month: 6, day: 15)

        let result = AppCalendar.addingDays(5, to: testDate)

        let calendar = Calendar.current
        #expect(calendar.component(.day, from: result) == 20)
    }

    @Test("AppCalendar.addingDays handles negative values")
    func addingDaysNegative() {
        let testDate = date(year: 2025, month: 6, day: 15)

        let result = AppCalendar.addingDays(-10, to: testDate)

        let calendar = Calendar.current
        #expect(calendar.component(.day, from: result) == 5)
    }

    // MARK: - weekdayLabel Tests

    @Test("AppCalendar.weekdayLabel returns abbreviated day")
    func weekdayLabelAbbreviated() {
        // Create a known Monday (Jan 6, 2025 is a Monday)
        let monday = date(year: 2025, month: 1, day: 6)

        let result = AppCalendar.weekdayLabel(for: monday)

        // Should be "Mon" or localized equivalent
        #expect(result.count <= 4) // Abbreviated format
    }

    // MARK: - dayID Tests

    @Test("AppCalendar.dayID is consistent for same day")
    func dayIDConsistent() {
        let date1 = date(year: 2025, month: 6, day: 15, hour: 9)
        let date2 = date(year: 2025, month: 6, day: 15, hour: 21)

        let id1 = AppCalendar.dayID(date1)
        let id2 = AppCalendar.dayID(date2)

        #expect(id1 == id2)
    }

    @Test("AppCalendar.dayID is different for different days")
    func dayIDDifferent() {
        let date1 = date(year: 2025, month: 6, day: 15)
        let date2 = date(year: 2025, month: 6, day: 16)

        let id1 = AppCalendar.dayID(date1)
        let id2 = AppCalendar.dayID(date2)

        #expect(id1 != id2)
    }

    @Test("AppCalendar.dayID starts with day_ prefix")
    func dayIDPrefix() {
        let testDate = date(year: 2025, month: 6, day: 15)

        let result = AppCalendar.dayID(testDate)

        #expect(result.hasPrefix("day_"))
    }
}
#endif
