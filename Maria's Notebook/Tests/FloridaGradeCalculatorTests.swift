#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("FloridaGradeCalculator Tests")
@MainActor
struct FloridaGradeCalculatorTests {

    // MARK: - schoolYearStart Tests

    @Test("School year start before September returns previous year's September")
    func schoolYearStartBeforeSeptember() {
        // Reference date in August should return previous year's September 1
        let referenceDate = TestCalendar.date(year: 2025, month: 8, day: 15)

        let result = FloridaGradeCalculator.schoolYearStart(for: referenceDate)

        let calendar = Calendar.current
        #expect(calendar.component(.year, from: result) == 2024)
        #expect(calendar.component(.month, from: result) == 9)
        #expect(calendar.component(.day, from: result) == 1)
    }

    @Test("School year start on or after September returns current year's September")
    func schoolYearStartAfterSeptember() {
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.schoolYearStart(for: referenceDate)

        let calendar = Calendar.current
        #expect(calendar.component(.year, from: result) == 2025)
        #expect(calendar.component(.month, from: result) == 9)
        #expect(calendar.component(.day, from: result) == 1)
    }

    @Test("School year start in December returns current year's September")
    func schoolYearStartInDecember() {
        let referenceDate = TestCalendar.date(year: 2025, month: 12, day: 15)

        let result = FloridaGradeCalculator.schoolYearStart(for: referenceDate)

        let calendar = Calendar.current
        #expect(calendar.component(.year, from: result) == 2025)
        #expect(calendar.component(.month, from: result) == 9)
    }

    // MARK: - ageOnSchoolYearStart Tests

    @Test("Age calculation for birthday before school year start")
    func ageBeforeSchoolStart() {
        // Birthday: June 15, 2019 (turns 6 by Sept 1, 2025)
        let birthday = TestCalendar.date(year: 2019, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 10, day: 1)

        let age = FloridaGradeCalculator.ageOnSchoolYearStart(birthday: birthday, referenceDate: referenceDate)

        #expect(age == 6)
    }

    @Test("Age calculation for birthday after school year start")
    func ageAfterSchoolStart() {
        // Birthday: October 15, 2019 (only 5 on Sept 1, 2025)
        let birthday = TestCalendar.date(year: 2019, month: 10, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 10, day: 1)

        let age = FloridaGradeCalculator.ageOnSchoolYearStart(birthday: birthday, referenceDate: referenceDate)

        #expect(age == 5)
    }

    @Test("Age calculation on exact school year start date")
    func ageOnExactSchoolStart() {
        // Birthday: September 1, 2019
        let birthday = TestCalendar.date(year: 2019, month: 9, day: 1)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let age = FloridaGradeCalculator.ageOnSchoolYearStart(birthday: birthday, referenceDate: referenceDate)

        #expect(age == 6)
    }

    // MARK: - grade() Tests - Kindergarten Cases

    @Test("Age 5 returns Kindergarten")
    func age5ReturnsKindergarten() {
        // Birthday: October 15, 2019 (age 5 on Sept 1, 2025)
        let birthday = TestCalendar.date(year: 2019, month: 10, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .kindergarten)
        #expect(result.displayString == "Kindergarten")
    }

    @Test("Age 4 returns Kindergarten")
    func age4ReturnsKindergarten() {
        let birthday = TestCalendar.date(year: 2020, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .kindergarten)
    }

    @Test("Age 3 returns Kindergarten")
    func age3ReturnsKindergarten() {
        let birthday = TestCalendar.date(year: 2021, month: 12, day: 1)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .kindergarten)
    }

    // MARK: - grade() Tests - Elementary Grades (1st-6th)

    @Test("Age 6 returns 1st Grade")
    func age6Returns1stGrade() {
        let birthday = TestCalendar.date(year: 2019, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .grade(1))
        #expect(result.displayString == "1st Grade")
    }

    @Test("Age 7 returns 2nd Grade")
    func age7Returns2ndGrade() {
        let birthday = TestCalendar.date(year: 2018, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .grade(2))
        #expect(result.displayString == "2nd Grade")
    }

    @Test("Age 8 returns 3rd Grade")
    func age8Returns3rdGrade() {
        let birthday = TestCalendar.date(year: 2017, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .grade(3))
        #expect(result.displayString == "3rd Grade")
    }

    @Test("Age 9 returns 4th Grade")
    func age9Returns4thGrade() {
        let birthday = TestCalendar.date(year: 2016, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .grade(4))
        #expect(result.displayString == "4th Grade")
    }

    @Test("Age 10 returns 5th Grade")
    func age10Returns5thGrade() {
        let birthday = TestCalendar.date(year: 2015, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .grade(5))
        #expect(result.displayString == "5th Grade")
    }

    @Test("Age 11 returns 6th Grade")
    func age11Returns6thGrade() {
        let birthday = TestCalendar.date(year: 2014, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .grade(6))
        #expect(result.displayString == "6th Grade")
    }

    // MARK: - grade() Tests - Graduated Cases

    @Test("Age 12 returns Graduated")
    func age12ReturnsGraduated() {
        let birthday = TestCalendar.date(year: 2013, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .graduated)
        #expect(result.displayString == "Graduated")
    }

    @Test("Age 13 returns Graduated")
    func age13ReturnsGraduated() {
        let birthday = TestCalendar.date(year: 2012, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .graduated)
    }

    @Test("Age 15 returns Graduated")
    func age15ReturnsGraduated() {
        let birthday = TestCalendar.date(year: 2010, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .graduated)
    }

    // MARK: - Edge Cases

    @Test("Birthday exactly on September 1 (early birthday)")
    func birthdayOnSeptember1() {
        // September 1 birthday means child turns age ON school year start
        let birthday = TestCalendar.date(year: 2019, month: 9, day: 1)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .grade(1)) // Age 6 on Sept 1
    }

    @Test("Birthday one day after September 1 (late birthday)")
    func birthdayOneDayAfterSeptember1() {
        // September 2 birthday means child is still age-1 on Sept 1
        let birthday = TestCalendar.date(year: 2019, month: 9, day: 2)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .kindergarten) // Age 5 on Sept 1
    }

    @Test("Leap year birthday handling")
    func leapYearBirthday() {
        // Birthday: Feb 29, 2016 (leap year)
        let birthday = TestCalendar.date(year: 2016, month: 2, day: 29)
        let referenceDate = TestCalendar.date(year: 2025, month: 9, day: 1)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        #expect(result == .grade(4)) // Age 9 on Sept 1, 2025
    }

    @Test("Reference date in middle of school year")
    func referenceDateMidYear() {
        // Even though reference is in January, should use Sept 1, 2024
        let birthday = TestCalendar.date(year: 2019, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 1, day: 15)

        let result = FloridaGradeCalculator.grade(for: birthday, referenceDate: referenceDate)

        // January 2025 -> school year started Sept 2024
        // Age on Sept 1, 2024 = 5 years old (birthday was June 2019)
        #expect(result == .kindergarten)
    }

    @Test("Grade result equality")
    func gradeResultEquality() {
        #expect(GradeResult.kindergarten == GradeResult.kindergarten)
        #expect(GradeResult.grade(1) == GradeResult.grade(1))
        #expect(GradeResult.grade(3) == GradeResult.grade(3))
        #expect(GradeResult.graduated == GradeResult.graduated)

        #expect(GradeResult.grade(1) != GradeResult.grade(2))
        #expect(GradeResult.kindergarten != GradeResult.grade(1))
        #expect(GradeResult.grade(6) != GradeResult.graduated)
    }
}

#endif
