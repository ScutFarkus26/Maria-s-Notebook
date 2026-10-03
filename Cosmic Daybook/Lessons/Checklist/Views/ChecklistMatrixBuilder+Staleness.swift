// ChecklistMatrixBuilder+Staleness.swift
// When open work counts as stale: the cell's "needs a check-in" dot.

import Foundation

extension ChecklistMatrixBuilder {
    /// Staleness threshold: 14 weekdays (approx 2.8 calendar weeks)
    static let staleWeekdays = 14

    /// Whether `lastActivity` is at least `staleWeekdays` weekdays before `today`.
    /// Clamped to the school-year counter epoch (see `SchoolYearCounters`), so work
    /// resting since last spring isn't stale on the first day of school.
    static func isStale(lastActivity: Date?, calendar: Calendar, today: Date) -> Bool {
        guard let lastActivity else { return false }
        let activityDay = calendar.startOfDay(for: SchoolYearCounters.countFrom(lastActivity))
        let totalDays = calendar.dateComponents([.day], from: activityDay, to: today).day ?? 0
        guard totalDays > 0 else { return false }
        let fullWeeks = totalDays / 7
        let remainingDays = totalDays % 7
        var weekdays = fullWeeks * 5
        let startWeekday = calendar.component(.weekday, from: activityDay)
        for offset in 0..<remainingDays {
            let dayOfWeek = (startWeekday - 1 + offset) % 7 + 1
            if dayOfWeek != 1 && dayOfWeek != 7 { weekdays += 1 }
        }
        return weekdays >= staleWeekdays
    }
}
