#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("AgeUtils Tests")
struct AgeUtilsTests {

    // MARK: - Test Helpers

    /// Creates a date from year, month, day components
    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    // MARK: - roundedAgeComponents Tests

    @Test("Exact year birthday returns whole years")
    func exactYearBirthday() {
        let birthday = date(year: 2020, month: 6, day: 15)
        let today = date(year: 2025, month: 6, day: 15)

        let result = AgeUtils.roundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 5)
        #expect(result.months == 0)
    }

    @Test("Partial year returns correct months")
    func partialYearMonths() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 4, day: 1)

        let result = AgeUtils.roundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 5)
        #expect(result.months == 3)
    }

    @Test("Days past half month rounds up to next month")
    func daysRoundUp() {
        let birthday = date(year: 2020, month: 1, day: 1)
        // January has 31 days, so 16+ days should round up
        let today = date(year: 2025, month: 1, day: 17)

        let result = AgeUtils.roundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 5)
        #expect(result.months == 1) // Rounded up from 0 months + 16 days
    }

    @Test("Days before half month stays at current month")
    func daysNoRoundUp() {
        let birthday = date(year: 2020, month: 1, day: 1)
        // January has 31 days, so < 16 days should not round up
        let today = date(year: 2025, month: 1, day: 10)

        let result = AgeUtils.roundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 5)
        #expect(result.months == 0)
    }

    @Test("11 months rolling to 12 adds a year")
    func monthsRollOver() {
        let birthday = date(year: 2020, month: 1, day: 1)
        // December with enough days to round the month up
        let today = date(year: 2025, month: 12, day: 20)

        let result = AgeUtils.roundedAgeComponents(birthday: birthday, today: today)

        // 11 months + ~20 days should round to 12 months = +1 year
        #expect(result.years == 6)
        #expect(result.months == 0)
    }

    @Test("Newborn returns 0 years 0 months")
    func newborn() {
        let birthday = date(year: 2025, month: 6, day: 1)
        let today = date(year: 2025, month: 6, day: 1)

        let result = AgeUtils.roundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 0)
        #expect(result.months == 0)
    }

    @Test("Baby under 1 year returns 0 years with months")
    func babyUnderOneYear() {
        let birthday = date(year: 2025, month: 1, day: 1)
        let today = date(year: 2025, month: 7, day: 1)

        let result = AgeUtils.roundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 0)
        #expect(result.months == 6)
    }

    // MARK: - quarterRoundedAgeComponents Tests

    @Test("Quarter rounding: 0-1 months rounds to 0")
    func quarterRound0Months() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 2, day: 1) // 1 month old in year 5

        let result = AgeUtils.quarterRoundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 5)
        #expect(result.months == 0)
    }

    @Test("Quarter rounding: 2-4 months rounds to 3")
    func quarterRound3Months() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 4, day: 1) // 3 months old in year 5

        let result = AgeUtils.quarterRoundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 5)
        #expect(result.months == 3)
    }

    @Test("Quarter rounding: 5-7 months rounds to 6")
    func quarterRound6Months() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 7, day: 1) // 6 months old in year 5

        let result = AgeUtils.quarterRoundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 5)
        #expect(result.months == 6)
    }

    @Test("Quarter rounding: 8-10 months rounds to 9")
    func quarterRound9Months() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 10, day: 1) // 9 months old in year 5

        let result = AgeUtils.quarterRoundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 5)
        #expect(result.months == 9)
    }

    @Test("Quarter rounding: 11 months rounds to next year")
    func quarterRound11Months() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 12, day: 1) // 11 months old in year 5

        let result = AgeUtils.quarterRoundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 6)
        #expect(result.months == 0)
    }

    // MARK: - verboseAgeString Tests

    @Test("Verbose string for exact years")
    func verboseExactYears() {
        let birthday = date(year: 2020, month: 6, day: 15)
        let today = date(year: 2025, month: 6, day: 15)

        let result = AgeUtils.verboseAgeString(for: birthday, today: today)

        #expect(result == "5 years")
    }

    @Test("Verbose string for 1 year singular")
    func verboseOneYear() {
        let birthday = date(year: 2024, month: 6, day: 15)
        let today = date(year: 2025, month: 6, day: 15)

        let result = AgeUtils.verboseAgeString(for: birthday, today: today)

        #expect(result == "1 year")
    }

    @Test("Verbose string for years and months")
    func verboseYearsAndMonths() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 4, day: 1)

        let result = AgeUtils.verboseAgeString(for: birthday, today: today)

        #expect(result == "5 years, 3 months")
    }

    @Test("Verbose string for 1 month singular")
    func verboseOneMonth() {
        let birthday = date(year: 2025, month: 1, day: 1)
        let today = date(year: 2025, month: 2, day: 1)

        let result = AgeUtils.verboseAgeString(for: birthday, today: today)

        #expect(result == "1 month")
    }

    @Test("Verbose string for months only under 1 year")
    func verboseMonthsOnly() {
        let birthday = date(year: 2025, month: 1, day: 1)
        let today = date(year: 2025, month: 6, day: 1)

        let result = AgeUtils.verboseAgeString(for: birthday, today: today)

        #expect(result == "5 months")
    }

    // MARK: - conciseAgeString Tests

    @Test("Concise string for exact years")
    func conciseExactYears() {
        let birthday = date(year: 2020, month: 6, day: 15)
        let today = date(year: 2025, month: 6, day: 15)

        let result = AgeUtils.conciseAgeString(for: birthday, today: today)

        #expect(result == "5 yr")
    }

    @Test("Concise string for 1 year singular")
    func conciseOneYear() {
        let birthday = date(year: 2024, month: 6, day: 15)
        let today = date(year: 2025, month: 6, day: 15)

        let result = AgeUtils.conciseAgeString(for: birthday, today: today)

        #expect(result == "1 yr")
    }

    @Test("Concise string for years and months")
    func conciseYearsAndMonths() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 4, day: 1)

        let result = AgeUtils.conciseAgeString(for: birthday, today: today)

        #expect(result == "5y 3m")
    }

    @Test("Concise string for 1 month singular")
    func conciseOneMonth() {
        let birthday = date(year: 2025, month: 1, day: 1)
        let today = date(year: 2025, month: 2, day: 1)

        let result = AgeUtils.conciseAgeString(for: birthday, today: today)

        #expect(result == "1 mo")
    }

    @Test("Concise string for months only")
    func conciseMonthsOnly() {
        let birthday = date(year: 2025, month: 1, day: 1)
        let today = date(year: 2025, month: 6, day: 1)

        let result = AgeUtils.conciseAgeString(for: birthday, today: today)

        #expect(result == "5 mo")
    }

    // MARK: - quarterFractionAgeString Tests

    @Test("Quarter fraction for whole year shows no fraction")
    func quarterFractionWholeYear() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2028, month: 1, day: 1)

        let result = AgeUtils.quarterFractionAgeString(for: birthday, today: today)

        #expect(result == "8")
    }

    @Test("Quarter fraction shows 1/4")
    func quarterFraction14() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2028, month: 4, day: 1) // 3 months into year 8

        let result = AgeUtils.quarterFractionAgeString(for: birthday, today: today)

        #expect(result == "8 1/4")
    }

    @Test("Quarter fraction shows 1/2")
    func quarterFraction12() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2028, month: 7, day: 1) // 6 months into year 8

        let result = AgeUtils.quarterFractionAgeString(for: birthday, today: today)

        #expect(result == "8 1/2")
    }

    @Test("Quarter fraction shows 3/4")
    func quarterFraction34() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2028, month: 10, day: 1) // 9 months into year 8

        let result = AgeUtils.quarterFractionAgeString(for: birthday, today: today)

        #expect(result == "8 3/4")
    }

    @Test("Quarter fraction under 1 year shows just fraction")
    func quarterFractionUnderYear() {
        let birthday = date(year: 2025, month: 1, day: 1)
        let today = date(year: 2025, month: 7, day: 1) // 6 months

        let result = AgeUtils.quarterFractionAgeString(for: birthday, today: today)

        #expect(result == "1/2")
    }

    @Test("Quarter fraction 0 years 0 months shows 0")
    func quarterFractionNewborn() {
        let birthday = date(year: 2025, month: 6, day: 1)
        let today = date(year: 2025, month: 6, day: 1)

        let result = AgeUtils.quarterFractionAgeString(for: birthday, today: today)

        #expect(result == "0")
    }

    // MARK: - halfYearRoundedAgeComponents Tests

    @Test("Half year rounding: 0-2 months rounds to no half")
    func halfYearNoHalf() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 3, day: 1) // 2 months

        let result = AgeUtils.halfYearRoundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 5)
        #expect(result.hasHalf == false)
    }

    @Test("Half year rounding: 3-8 months rounds to half")
    func halfYearHasHalf() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 7, day: 1) // 6 months

        let result = AgeUtils.halfYearRoundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 5)
        #expect(result.hasHalf == true)
    }

    @Test("Half year rounding: 9-11 months rounds to next year")
    func halfYearNextYear() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2025, month: 11, day: 1) // 10 months

        let result = AgeUtils.halfYearRoundedAgeComponents(birthday: birthday, today: today)

        #expect(result.years == 6)
        #expect(result.hasHalf == false)
    }

    // MARK: - halfYearAgeString Tests

    @Test("Half year string whole number")
    func halfYearStringWhole() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2027, month: 1, day: 1)

        let result = AgeUtils.halfYearAgeString(for: birthday, today: today)

        #expect(result == "7")
    }

    @Test("Half year string with half")
    func halfYearStringWithHalf() {
        let birthday = date(year: 2020, month: 1, day: 1)
        let today = date(year: 2028, month: 7, day: 1) // 6 months into year 8

        let result = AgeUtils.halfYearAgeString(for: birthday, today: today)

        #expect(result == "8 1/2")
    }

    @Test("Half year string under 1 year with half")
    func halfYearStringUnder1YearHalf() {
        let birthday = date(year: 2025, month: 1, day: 1)
        let today = date(year: 2025, month: 7, day: 1) // 6 months

        let result = AgeUtils.halfYearAgeString(for: birthday, today: today)

        #expect(result == "1/2")
    }

    @Test("Half year string under 1 year no half")
    func halfYearStringUnder1YearNoHalf() {
        let birthday = date(year: 2025, month: 1, day: 1)
        let today = date(year: 2025, month: 2, day: 1) // 1 month

        let result = AgeUtils.halfYearAgeString(for: birthday, today: today)

        #expect(result == "0")
    }

    // MARK: - Edge Cases

    @Test("Leap year birthday Feb 29")
    func leapYearBirthday() {
        let birthday = date(year: 2020, month: 2, day: 29) // Leap year
        let today = date(year: 2025, month: 2, day: 28) // Non-leap year

        let result = AgeUtils.roundedAgeComponents(birthday: birthday, today: today)

        // Feb 29, 2020 to Feb 28, 2025 is 4 years, 11 months, 30 days
        // Since 30 days is more than half of the month (28 days in Feb 2025), it rounds up
        #expect(result.years == 5)
        #expect(result.months == 0)
    }

    @Test("Very old age 100 years")
    func veryOldAge() {
        let birthday = date(year: 1920, month: 1, day: 1)
        let today = date(year: 2025, month: 6, day: 15)

        let result = AgeUtils.roundedAgeComponents(birthday: birthday, today: today)

        // Jan 1, 1920 to June 15, 2025 is 105 years, 5 months, 14 days
        // 14 days is less than half of June (30 days), so doesn't round up
        #expect(result.years == 105)
        #expect(result.months == 5)
    }
}
#endif
