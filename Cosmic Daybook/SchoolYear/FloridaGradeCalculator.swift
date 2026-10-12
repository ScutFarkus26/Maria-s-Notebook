// FloridaGradeCalculator.swift
// Determines Florida grade equivalents from a birthday: age on September 1 of the
// school year under way (Florida's fixed cutoff), whatever day the class's own
// school year starts on. The configurable start still decides which school year
// that is, and is what attendance and the other year-start callers read.

import Foundation

/// Semantic grade result used by the calculator and UI.
enum GradeResult: Equatable {
    case kindergarten
    case grade(Int)   // 1...8
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

    /// Month of the school year start. Configurable via Settings; defaults to September.
    /// Read from `UserDefaultsKeys.schoolYearStartMonth` so the grade boundary and the
    /// school-year viewing lens (`SchoolYearStore`) stay in lockstep.
    static var schoolStartMonth: Int {
        let value = UserDefaults.standard.integer(forKey: UserDefaultsKeys.schoolYearStartMonth)
        return (1...12).contains(value) ? value : 9
    }
    /// Day of the school year start. Configurable via Settings; defaults to the 1st.
    static var schoolStartDay: Int {
        let value = UserDefaults.standard.integer(forKey: UserDefaultsKeys.schoolYearStartDay)
        return (1...31).contains(value) ? value : 1
    }
    /// Florida's grade cutoff: a child's grade follows her age on September 1,
    /// the date the grade guidelines in Settings name. Fixed, not the class's
    /// configured start: with the year starting August 25, a child born
    /// August 26 – September 1 came out a grade off (2026-10-11 hunt, #38).
    static let gradeCutoffMonth: Int = 9
    static let gradeCutoffDay: Int = 1
    /// Minimum age (in whole years) on/before school start to be 1st grade
    static let minimumFirstGradeAge: Int = 6
    /// Ages at or above this threshold are considered "Graduated".
    /// 14, not 12: ages 12–13 are the Adolescent level (7th/8th grade equivalents).
    static let graduatedAgeThreshold: Int = 14

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

    /// September 1 of the school year under way on `referenceDate`: the
    /// configured start says which school year that is (so the week between an
    /// August 25 start and September 1 already counts as the new year), and the
    /// cutoff is that year's September 1.
    static func gradeCutoff(for referenceDate: Date = Date(), calendar: Calendar = .current) -> Date {
        let beginYear = calendar.component(.year, from: schoolYearStart(for: referenceDate, calendar: calendar))
        let components = DateComponents(year: beginYear, month: gradeCutoffMonth, day: gradeCutoffDay)
        return calendar.date(from: components) ?? schoolYearStart(for: referenceDate, calendar: calendar)
    }

    /// Computes the child's age in whole years as of the grade cutoff
    /// (September 1 of the school year under way).
    /// Uses start-of-day normalization to avoid time-of-day issues.
    static func ageOnSchoolYearStart(
        birthday: Date,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let cutoff = gradeCutoff(for: referenceDate, calendar: calendar)
        let birthdayStartOfDay = calendar.startOfDay(for: birthday)
        return calendar.dateComponents([.year], from: birthdayStartOfDay, to: cutoff).year ?? 0
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
    ///  - Age 12 → 7th Grade
    ///  - Age 13 → 8th Grade
    ///  - Age 14+ → Graduated
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
