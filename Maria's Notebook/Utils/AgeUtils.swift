// AgeUtils.swift
// Age formatting utilities (rounded, quarter, half-year, and fraction strings).
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation

/// Age range filter for filtering students by age groups
enum AgeRange: String, CaseIterable, Identifiable, Hashable {
    case under3 = "Under 3"
    case age3 = "3 years"
    case age4 = "4 years"
    case age5 = "5 years"
    case age6 = "6 years"
    case age7 = "7 years"
    case age8 = "8 years"
    case age9 = "9 years"
    case age10 = "10 years"
    case age11 = "11 years"
    case age12plus = "12+ years"
    
    var id: String { rawValue }
    
    /// Check if a birthday falls within this age range
    func contains(_ birthday: Date, calendar: Calendar = .current) -> Bool {
        let age = AgeUtils.quarterRoundedAgeComponents(birthday: birthday, today: Date(), calendar: calendar)
        let years = age.years
        
        switch self {
        case .under3:
            return years < 3
        case .age3:
            return years == 3
        case .age4:
            return years == 4
        case .age5:
            return years == 5
        case .age6:
            return years == 6
        case .age7:
            return years == 7
        case .age8:
            return years == 8
        case .age9:
            return years == 9
        case .age10:
            return years == 10
        case .age11:
            return years == 11
        case .age12plus:
            return years >= 12
        }
    }
    
    /// Check if a birthday matches any of the selected age ranges
    static func matchesAny(_ birthday: Date, in selectedRanges: Set<AgeRange>, calendar: Calendar = .current) -> Bool {
        guard !selectedRanges.isEmpty else { return true }
        return selectedRanges.contains { $0.contains(birthday, calendar: calendar) }
    }
}

/// Utilities for computing and formatting ages in different rounding schemes.
/// All functions are pure and side-effect free.
struct AgeUtils {
    // MARK: - Core Computations

    /// Returns (years, months) rounded by pushing days >= half a month up to the next month.
    static func roundedAgeComponents(birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> (years: Int, months: Int) {
        let comps = calendar.dateComponents([.year, .month, .day], from: birthday, to: today)
        var years = comps.year ?? 0
        var months = comps.month ?? 0
        let days = comps.day ?? 0

        if let anchor = calendar.date(byAdding: DateComponents(year: years, month: months), to: birthday),
           let daysInThisMonth = calendar.range(of: .day, in: .month, for: anchor)?.count {
            if days * 2 >= daysInThisMonth { months += 1 }
        }

        if months >= 12 {
            years += months / 12
            months = months % 12
        }

        return (max(0, years), max(0, months))
    }

    /// Returns (years, months) rounded to the nearest quarter year (months in {0,3,6,9}).
    static func quarterRoundedAgeComponents(birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> (years: Int, months: Int) {
        // Start from month-rounded components (push days >= half a month up)
        let base = roundedAgeComponents(birthday: birthday, today: today, calendar: calendar)
        var years = base.years
        let months = base.months

        // Round months to nearest quarter (3-month increments)
        let roundedQuarterMonths = Int((Double(months) / 3.0).rounded()) * 3

        if roundedQuarterMonths >= 12 {
            years += 1
            return (max(0, years), 0)
        } else {
            return (max(0, years), roundedQuarterMonths)
        }
    }

    // MARK: - Verbose Strings

    /// Verbose age string like "2 years, 3 months", handling singulars and zero-parts.
    static func verboseAgeString(for birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let age = roundedAgeComponents(birthday: birthday, today: today, calendar: calendar)
        let y = age.years, m = age.months
        if y == 0 { return m == 1 ? "1 month" : "\(m) months" }
        if m == 0 { return y == 1 ? "1 year" : "\(y) years" }
        return "\(y) years, \(m) months"
    }

    /// Verbose quarter-rounded age string like "2 years, 3 months" where months ∈ {0,3,6,9}.
    static func verboseQuarterAgeString(for birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let age = quarterRoundedAgeComponents(birthday: birthday, today: today, calendar: calendar)
        let y = age.years, m = age.months
        if y == 0 { return m == 1 ? "1 month" : "\(m) months" }
        if m == 0 { return y == 1 ? "1 year" : "\(y) years" }
        return "\(y) years, \(m) months"
    }

    // MARK: - Concise Strings

    /// Concise age string like "2y 3m", handling singulars and zero-parts.
    static func conciseAgeString(for birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let age = roundedAgeComponents(birthday: birthday, today: today, calendar: calendar)
        let y = age.years, m = age.months
        if y == 0 { return m == 1 ? "1 mo" : "\(m) mo" }
        if m == 0 { return y == 1 ? "1 yr" : "\(y) yr" }
        return "\(y)y \(m)m"
    }

    /// Concise quarter-rounded age string like "2y 3m" where months ∈ {0,3,6,9}.
    static func conciseQuarterAgeString(for birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let age = quarterRoundedAgeComponents(birthday: birthday, today: today, calendar: calendar)
        let y = age.years, m = age.months
        if y == 0 { return m == 1 ? "1 mo" : "\(m) mo" }
        if m == 0 { return y == 1 ? "1 yr" : "\(y) yr" }
        return "\(y)y \(m)m"
    }

    // MARK: - Fraction / Half-Year

    /// Quarter-fraction age string like "8 1/4", "8 1/2", "8 3/4"; under 1 year shows "1/4", "1/2", or "3/4" (or "0").
    static func quarterFractionAgeString(for birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let age = quarterRoundedAgeComponents(birthday: birthday, today: today, calendar: calendar)
        let y = age.years
        let m = age.months
        let fraction: String
        switch m {
        case 0:
            fraction = ""
        case 3:
            fraction = " 1/4"
        case 6:
            fraction = " 1/2"
        case 9:
            fraction = " 3/4"
        default:
            // Fallback: should not happen because quarterRoundedAgeComponents yields 0,3,6,9
            fraction = ""
        }
        if y == 0 {
            return fraction.isEmpty ? "0" : fraction.trimmingCharacters(in: .whitespaces)
        }
        return "\(y)\(fraction)"
    }

    /// Returns (years, hasHalf) where hasHalf indicates rounding to the nearest half-year.
    /// Months are rounded to the nearest 0, 6, or 12; 12 months carries to the next year.
    static func halfYearRoundedAgeComponents(birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> (years: Int, hasHalf: Bool) {
        // Start from month-rounded components (push days >= half a month up)
        let base = roundedAgeComponents(birthday: birthday, today: today, calendar: calendar)
        var years = max(0, base.years)
        let months = max(0, base.months)

        // Round months to nearest half-year (0, 6, 12)
        let bucket = Int((Double(months) / 6.0).rounded()) // 0, 1, or 2
        switch bucket {
        case 0:
            return (years, false)
        case 1:
            return (years, true)
        default:
            years += 1
            return (years, false)
        }
    }

    /// Returns a half-year age string like "7" or "8 1/2".
    /// If under 1 year, returns "1/2" when appropriate, otherwise "0".
    static func halfYearAgeString(for birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let age = halfYearRoundedAgeComponents(birthday: birthday, today: today, calendar: calendar)
        if age.years == 0 {
            return age.hasHalf ? "1/2" : "0"
        }
        return age.hasHalf ? "\(age.years) 1/2" : "\(age.years)"
    }
}
