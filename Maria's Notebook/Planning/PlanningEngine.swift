import Foundation

enum PlanningEngine {
    static func firstSchoolDay(onOrAfter date: Date, calendar: Calendar, isNonSchoolDay: (Date) -> Bool) -> Date {
        var d = date
        while isNonSchoolDay(d) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return d
    }

    static func moveBySchoolDays(from start: Date, days: Int, calendar: Calendar, isNonSchoolDay: (Date) -> Bool) -> Date {
        var count = abs(days)
        let forward = days >= 0
        var d = start
        while count > 0 {
            guard let next = calendar.date(byAdding: .day, value: forward ? 1 : -1, to: d) else { break }
            d = next
            if !isNonSchoolDay(d) { count -= 1 }
        }
        return d
    }

    static func days(from start: Date, window: Int, calendar: Calendar) -> [Date] {
        (0..<window).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func dayName(_ day: Date) -> String {
        day.formatted(Date.FormatStyle().weekday(.abbreviated))
    }

    static func dayNumber(_ day: Date) -> String {
        day.formatted(Date.FormatStyle().day())
    }

    static func dayShortLabel(_ day: Date) -> String {
        day.formatted(Date.FormatStyle().weekday(.abbreviated).day())
    }

    static func dateForSlot(day: Date, period: DayPeriod, calendar: Calendar) -> Date {
        let startOfDay = AppCalendar.startOfDay(day)
        return calendar.date(byAdding: .hour, value: period.baseHour, to: startOfDay) ?? startOfDay
    }

    @available(*, deprecated, message: "Legacy WorkModel-based planning helpers have been retired. Returns empty.")
    static func unscheduledWorks(_ works: [WorkModel]) -> [WorkModel] {
        return []
    }

    @available(*, deprecated, message: "Legacy WorkModel-based planning helpers have been retired. Returns empty.")
    static func groupedItems(works: [WorkModel], calendar: Calendar) -> [DayKey: [ScheduledItem]] {
        return [:]
    }
}
