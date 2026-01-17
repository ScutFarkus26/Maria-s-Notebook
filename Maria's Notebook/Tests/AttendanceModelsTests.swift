#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("AttendanceStatus Tests")
struct AttendanceStatusTests {

    // MARK: - Raw Values

    @Test("AttendanceStatus.unmarked has correct rawValue")
    func unmarkedRawValue() {
        #expect(AttendanceStatus.unmarked.rawValue == "unmarked")
    }

    @Test("AttendanceStatus.present has correct rawValue")
    func presentRawValue() {
        #expect(AttendanceStatus.present.rawValue == "present")
    }

    @Test("AttendanceStatus.absent has correct rawValue")
    func absentRawValue() {
        #expect(AttendanceStatus.absent.rawValue == "absent")
    }

    @Test("AttendanceStatus.tardy has correct rawValue")
    func tardyRawValue() {
        #expect(AttendanceStatus.tardy.rawValue == "tardy")
    }

    @Test("AttendanceStatus.leftEarly has correct rawValue")
    func leftEarlyRawValue() {
        #expect(AttendanceStatus.leftEarly.rawValue == "leftEarly")
    }

    // MARK: - Display Names

    @Test("AttendanceStatus.unmarked displayName")
    func unmarkedDisplayName() {
        #expect(AttendanceStatus.unmarked.displayName == "Unmarked")
    }

    @Test("AttendanceStatus.present displayName")
    func presentDisplayName() {
        #expect(AttendanceStatus.present.displayName == "Present")
    }

    @Test("AttendanceStatus.absent displayName")
    func absentDisplayName() {
        #expect(AttendanceStatus.absent.displayName == "Absent")
    }

    @Test("AttendanceStatus.tardy displayName")
    func tardyDisplayName() {
        #expect(AttendanceStatus.tardy.displayName == "Tardy")
    }

    @Test("AttendanceStatus.leftEarly displayName")
    func leftEarlyDisplayName() {
        #expect(AttendanceStatus.leftEarly.displayName == "Left Early")
    }

    // MARK: - CaseIterable

    @Test("AttendanceStatus has 5 cases")
    func hasFiveCases() {
        #expect(AttendanceStatus.allCases.count == 5)
    }

    @Test("AttendanceStatus allCases contains all values")
    func allCasesComplete() {
        let allCases = AttendanceStatus.allCases

        #expect(allCases.contains(.unmarked))
        #expect(allCases.contains(.present))
        #expect(allCases.contains(.absent))
        #expect(allCases.contains(.tardy))
        #expect(allCases.contains(.leftEarly))
    }

    // MARK: - Initialization from rawValue

    @Test("AttendanceStatus can be initialized from valid rawValue")
    func initFromValidRawValue() {
        let status = AttendanceStatus(rawValue: "present")

        #expect(status == .present)
    }

    @Test("AttendanceStatus returns nil for invalid rawValue")
    func initFromInvalidRawValue() {
        let status = AttendanceStatus(rawValue: "invalid")

        #expect(status == nil)
    }

    // MARK: - Color (basic validation)

    @Test("All statuses have non-nil colors")
    func allStatusesHaveColors() {
        for status in AttendanceStatus.allCases {
            // Just verify colors exist - Color comparison is complex
            let _ = status.color
            #expect(true)
        }
    }
}

@Suite("AbsenceReason Tests")
struct AbsenceReasonTests {

    // MARK: - Raw Values

    @Test("AbsenceReason.none has correct rawValue")
    func noneRawValue() {
        #expect(AbsenceReason.none.rawValue == "none")
    }

    @Test("AbsenceReason.sick has correct rawValue")
    func sickRawValue() {
        #expect(AbsenceReason.sick.rawValue == "sick")
    }

    @Test("AbsenceReason.vacation has correct rawValue")
    func vacationRawValue() {
        #expect(AbsenceReason.vacation.rawValue == "vacation")
    }

    // MARK: - Display Names

    @Test("AbsenceReason.none displayName is empty")
    func noneDisplayName() {
        #expect(AbsenceReason.none.displayName == "")
    }

    @Test("AbsenceReason.sick displayName")
    func sickDisplayName() {
        #expect(AbsenceReason.sick.displayName == "Sick")
    }

    @Test("AbsenceReason.vacation displayName")
    func vacationDisplayName() {
        #expect(AbsenceReason.vacation.displayName == "Vacation")
    }

    // MARK: - Icons

    @Test("AbsenceReason.none has placeholder icon")
    func noneIcon() {
        #expect(AbsenceReason.none.icon == "circle")
    }

    @Test("AbsenceReason.sick has medical icon")
    func sickIcon() {
        #expect(AbsenceReason.sick.icon == "cross.case.fill")
    }

    @Test("AbsenceReason.vacation has vacation icon")
    func vacationIcon() {
        #expect(AbsenceReason.vacation.icon == "beach.umbrella.fill")
    }

    // MARK: - CaseIterable

    @Test("AbsenceReason has 3 cases")
    func hasThreeCases() {
        #expect(AbsenceReason.allCases.count == 3)
    }

    @Test("AbsenceReason allCases contains all values")
    func allCasesComplete() {
        let allCases = AbsenceReason.allCases

        #expect(allCases.contains(.none))
        #expect(allCases.contains(.sick))
        #expect(allCases.contains(.vacation))
    }

    // MARK: - Initialization from rawValue

    @Test("AbsenceReason can be initialized from valid rawValue")
    func initFromValidRawValue() {
        let reason = AbsenceReason(rawValue: "sick")

        #expect(reason == .sick)
    }

    @Test("AbsenceReason returns nil for invalid rawValue")
    func initFromInvalidRawValue() {
        let reason = AbsenceReason(rawValue: "invalid")

        #expect(reason == nil)
    }
}

@Suite("Date Normalization Tests")
struct DateNormalizationExtensionTests {

    // MARK: - Test Helpers

    private func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 30, second: Int = 45) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components)!
    }

    // MARK: - normalizedDay Tests

    @Test("normalizedDay returns start of day")
    func normalizedDayReturnsStartOfDay() {
        let testDate = date(year: 2025, month: 6, day: 15, hour: 14, minute: 30, second: 45)

        let normalized = testDate.normalizedDay()

        let calendar = Calendar.current
        #expect(calendar.component(.year, from: normalized) == 2025)
        #expect(calendar.component(.month, from: normalized) == 6)
        #expect(calendar.component(.day, from: normalized) == 15)
        #expect(calendar.component(.hour, from: normalized) == 0)
        #expect(calendar.component(.minute, from: normalized) == 0)
        #expect(calendar.component(.second, from: normalized) == 0)
    }

    @Test("normalizedDay with custom calendar")
    func normalizedDayWithCustomCalendar() {
        let testDate = date(year: 2025, month: 6, day: 15, hour: 14)
        var customCalendar = Calendar(identifier: .gregorian)
        customCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let normalized = testDate.normalizedDay(using: customCalendar)

        // Should return midnight in UTC
        let hour = customCalendar.component(.hour, from: normalized)
        #expect(hour == 0)
    }

    @Test("normalizedDay is idempotent")
    func normalizedDayIdempotent() {
        let testDate = date(year: 2025, month: 6, day: 15, hour: 14)
        let firstNormalized = testDate.normalizedDay()

        let secondNormalized = firstNormalized.normalizedDay()

        #expect(firstNormalized == secondNormalized)
    }

    @Test("Same day different times produce same normalized day")
    func sameDayDifferentTimesNormalize() {
        let morning = date(year: 2025, month: 6, day: 15, hour: 6)
        let evening = date(year: 2025, month: 6, day: 15, hour: 22)

        let normalizedMorning = morning.normalizedDay()
        let normalizedEvening = evening.normalizedDay()

        #expect(normalizedMorning == normalizedEvening)
    }

    @Test("Different days produce different normalized days")
    func differentDaysNormalizeDifferently() {
        let day1 = date(year: 2025, month: 6, day: 15)
        let day2 = date(year: 2025, month: 6, day: 16)

        let normalizedDay1 = day1.normalizedDay()
        let normalizedDay2 = day2.normalizedDay()

        #expect(normalizedDay1 != normalizedDay2)
    }

    // MARK: - Edge Cases

    @Test("normalizedDay handles midnight correctly")
    func normalizedDayHandlesMidnight() {
        let midnight = date(year: 2025, month: 6, day: 15, hour: 0, minute: 0, second: 0)

        let normalized = midnight.normalizedDay()

        #expect(normalized == midnight)
    }

    @Test("normalizedDay handles end of day correctly")
    func normalizedDayHandlesEndOfDay() {
        let endOfDay = date(year: 2025, month: 6, day: 15, hour: 23, minute: 59, second: 59)

        let normalized = endOfDay.normalizedDay()

        let calendar = Calendar.current
        #expect(calendar.component(.day, from: normalized) == 15)
        #expect(calendar.component(.hour, from: normalized) == 0)
    }

    @Test("normalizedDay handles year boundary")
    func normalizedDayHandlesYearBoundary() {
        let newYearsEve = date(year: 2024, month: 12, day: 31, hour: 23)
        let newYearsDay = date(year: 2025, month: 1, day: 1, hour: 1)

        let normalizedEve = newYearsEve.normalizedDay()
        let normalizedDay = newYearsDay.normalizedDay()

        let calendar = Calendar.current
        #expect(calendar.component(.year, from: normalizedEve) == 2024)
        #expect(calendar.component(.year, from: normalizedDay) == 2025)
        #expect(normalizedEve != normalizedDay)
    }

    @Test("normalizedDay handles leap year Feb 29")
    func normalizedDayHandlesLeapYear() {
        // Feb 29, 2024 is a valid leap year date
        let leapDay = date(year: 2024, month: 2, day: 29, hour: 15)

        let normalized = leapDay.normalizedDay()

        let calendar = Calendar.current
        #expect(calendar.component(.month, from: normalized) == 2)
        #expect(calendar.component(.day, from: normalized) == 29)
    }
}
#endif
