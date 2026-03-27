import Foundation

// MARK: - US Federal Holidays

enum PerpetualHolidays {
    static func holiday(month: Int, day: Int, year: Int) -> String? {
        if let fixed = fixedHoliday(month: month, day: day) {
            return fixed
        }
        return floatingHoliday(month: month, day: day, year: year)
    }

    private static func fixedHoliday(month: Int, day: Int) -> String? {
        switch (month, day) {
        case (1, 1):   return "New Year's Day"
        case (6, 19):  return "Juneteenth"
        case (7, 4):   return "Independence Day"
        case (11, 11): return "Veterans Day"
        case (12, 25): return "Christmas Day"
        default:       return nil
        }
    }

    private static func floatingHoliday(month: Int, day: Int, year: Int) -> String? {
        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = cal.date(from: comps) else { return nil }
        let weekday = cal.component(.weekday, from: date)
        let weekOfMonth = (day - 1) / 7 + 1

        switch (month, weekday, weekOfMonth) {
        case (1, 2, 3):  return "MLK Day"
        case (2, 2, 3):  return "Presidents' Day"
        case (5, 2, _) where isLastOccurrence(day: day, month: month, year: year):
            return "Memorial Day"
        case (9, 2, 1):  return "Labor Day"
        case (10, 2, 2): return "Columbus Day"
        case (11, 5, 4): return "Thanksgiving"
        default: return nil
        }
    }

    private static func isLastOccurrence(day: Int, month: Int, year: Int) -> Bool {
        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = cal.date(from: comps),
              let nextWeek = cal.date(byAdding: .day, value: 7, to: date) else { return false }
        return cal.component(.month, from: nextWeek) != month
    }
}
