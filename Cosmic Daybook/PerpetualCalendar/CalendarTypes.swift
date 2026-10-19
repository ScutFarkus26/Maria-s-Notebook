import Foundation

// MARK: - Shared Calendar Grid Types

/// Identifies a specific month in the perpetual calendar grid.
struct MonthID: Hashable, Identifiable {
    let year: Int
    let month: Int
    var id: Int { year * 12 + month }
}

/// Identifies a specific day cell in the perpetual calendar grid.
struct CellID: Hashable {
    let year: Int
    let month: Int
    let day: Int
}

// MARK: - Days

extension CellID {

    /// The cell `date` falls on, in the app's calendar (`AppCalendar`).
    init(date: Date) {
        let parts = AppCalendar.shared.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// The start of this day in the app's calendar, the key a day pad is
    /// kept under; nil for a day the calendar doesn't have (30 February),
    /// which it would otherwise roll over into March.
    func startOfDay() -> Date? {
        let calendar = AppCalendar.shared
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard parts.year == year, parts.month == month, parts.day == day else { return nil }
        return AppCalendar.startOfDay(date)
    }
}
