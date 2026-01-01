// FloridaGradeCalculator.swift
// Determines Florida grade equivalents based on birthday and configurable school-year start.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation

/// Semantic grade result used by the calculator and UI.
enum GradeResult: Equatable {
    case kindergarten
    case grade(Int)   // 1...6
    case graduated

    var displayString: String {
        switch self {
        case .kindergarten:
            return "Kindergarten"
        case .graduated:
            return "Graduated"
        case .grade(let n):
            func ordinal(_ n: Int) -> String {
                switch n {
                case 1: return "1st"
                case 2: return "2nd"
                case 3: return "3rd"
                case 4: return "4th"
                case 5: return "5th"
                case 6: return "6th"
                default: return "\(n)th"
                }
            }
            return "\(ordinal(n)) Grade"
        }
    }
}

/// Grade calculation helpers with configurable constants for school-year boundaries.
/// All functions are pure computations.
struct FloridaGradeCalculator {
    // MARK: - Configuration

    /// Month of the school year start (default: September)
    static var schoolStartMonth: Int = 9
    /// Day of the school year start (default: 1st)
    static var schoolStartDay: Int = 1
    /// Minimum age (in whole years) on/before school start to be 1st grade (default: 6)
    static var minimumFirstGradeAge: Int = 6
    /// Ages at or above this threshold are considered "Graduated" (default: 12)
    static var graduatedAgeThreshold: Int = 12

    // MARK: - Helpers

    /// Computes September 1 (or your configured start) for the proper school year
    /// relative to the given reference date.
    static func schoolYearStart(for referenceDate: Date = Date(), calendar: Calendar = .current) -> Date {
        let year = calendar.component(.year, from: referenceDate)
        var components = DateComponents(year: year, month: schoolStartMonth, day: schoolStartDay)
        let startThisYear = calendar.date(from: components)!
        if referenceDate < startThisYear {
            components.year = year - 1
            return calendar.date(from: components) ?? startThisYear
        } else {
            return startThisYear
        }
    }

    /// Computes the child's age in whole years as of the school year start.
    static func ageOnSchoolYearStart(birthday: Date, referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = schoolYearStart(for: referenceDate, calendar: calendar)
        return calendar.dateComponents([.year], from: birthday, to: start).year ?? 0
    }

    // MARK: - Public API

    /// Determines the grade result for a given birthday using Florida's rule.
    /// Mapping:
    ///  - Age 6 → 1st Grade
    ///  - Age 7 → 2nd Grade
    ///  - Age 8 → 3rd Grade
    ///  - Age 9 → 4th Grade
    ///  - Age 10 → 5th Grade
    ///  - Age 11 → 6th Grade
    ///  - Age 12+ → Graduated
    ///  - Age < 6 → Kindergarten
    static func grade(for birthday: Date, referenceDate: Date = Date(), calendar: Calendar = .current) -> GradeResult {
        let age = ageOnSchoolYearStart(birthday: birthday, referenceDate: referenceDate, calendar: calendar)
        if age >= graduatedAgeThreshold {
            return .graduated
        } else if age >= minimumFirstGradeAge {
            // Formula: grade = age - 5
            let gradeNumber = age - (minimumFirstGradeAge - 1)
            return .grade(gradeNumber)
        } else {
            return .kindergarten
        }
    }
}

