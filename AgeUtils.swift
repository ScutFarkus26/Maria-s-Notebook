import Foundation

struct AgeUtils {
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

    /// Verbose age string like "2 years, 3 months", handling singulars and zero-parts.
    static func verboseAgeString(for birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let age = roundedAgeComponents(birthday: birthday, today: today, calendar: calendar)
        let y = age.years, m = age.months
        if y == 0 { return m == 1 ? "1 month" : "\(m) months" }
        if m == 0 { return y == 1 ? "1 year" : "\(y) years" }
        return "\(y) years, \(m) months"
    }

    /// Concise age string like "2y 3m", handling singulars and zero-parts.
    static func conciseAgeString(for birthday: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let age = roundedAgeComponents(birthday: birthday, today: today, calendar: calendar)
        let y = age.years, m = age.months
        if y == 0 { return m == 1 ? "1 mo" : "\(m) mo" }
        if m == 0 { return y == 1 ? "1 yr" : "\(y) yr" }
        return "\(y)y \(m)m"
    }
}
