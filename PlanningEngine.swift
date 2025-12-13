import Foundation
import SwiftData

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

    static func dayID(_ day: Date, calendar: Calendar) -> String {
        // Kept signature for backwards compatibility; calendar is not used.
        AppCalendar.dayID(day)
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

    static func unscheduledWorks(_ works: [WorkModel]) -> [WorkModel] {
        works
            .filter { $0.isOpen && !$0.checkIns.contains(where: { $0.status != .completed && $0.status != .skipped }) }
            .sorted(by: { $0.createdAt < $1.createdAt })
    }

    static func dateForSlot(day: Date, period: DayPeriod, calendar: Calendar) -> Date {
        let startOfDay = AppCalendar.startOfDay(day)
        return calendar.date(byAdding: .hour, value: period.baseHour, to: startOfDay) ?? startOfDay
    }

    static func groupedItems(works: [WorkModel], calendar: Calendar) -> [DayKey: [ScheduledItem]] {
        var result: [DayKey: [ScheduledItem]] = [:]
        for work in works where work.isOpen {
            for ci in work.checkIns where ci.status != .completed && ci.status != .skipped {
                let dayStart = AppCalendar.startOfDay(ci.date)
                let hour = calendar.component(.hour, from: ci.date)
                let period: DayPeriod = hour < 12 ? .morning : .afternoon
                let key = DayKey(dayStart: dayStart, period: period)
                result[key, default: []].append(ScheduledItem(work: work, checkIn: ci))
            }
        }
        for key in result.keys {
            result[key]?.sort { $0.checkIn.date < $1.checkIn.date }
        }
        return result
    }
}
