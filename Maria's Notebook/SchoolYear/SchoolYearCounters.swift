// SchoolYearCounters.swift
// The counter epoch: the day every "days since…" counter starts over on.
//
// Elapsed-day counters — school days since the last lesson, days since the last meeting,
// how long a work item has gone untouched — measure from the last activity date. Across a
// summer that produces numbers that describe the calendar rather than the child, and on the
// first morning of school every child looks neglected. The epoch fixes that: it clamps each
// counter's start date forward, so a lesson given last May counts from the first day of the
// new year and reads 0 on that day.
//
// Nothing is written or deleted — the underlying dates are untouched, and clearing the epoch
// (Settings → School Calendar → "Count from: All history") restores the old behavior exactly.
//
// Reads are `nonisolated static` so the off-main aging engines can use them the same way
// `FloridaGradeCalculator` reads the school-year start. `SchoolYearStore` owns the writes.

import Foundation

enum SchoolYearCounters {
    /// The day counters count from, or nil when they count the full history.
    nonisolated static var epoch: Date? {
        guard let raw = UserDefaults.standard.object(forKey: UserDefaultsKeys.schoolYearCounterEpoch) as? Double
        else { return nil }
        return Date(timeIntervalSinceReferenceDate: raw)
    }

    /// True when counters restart at the school-year start rather than running from all history.
    nonisolated static var isResetting: Bool { epoch != nil }

    /// Clamps an activity date forward to the epoch. Dates on or after the epoch are returned
    /// unchanged, so this is a no-op for everything that happened this school year.
    nonisolated static func countFrom(_ date: Date) -> Date {
        guard let epoch else { return date }
        return max(date, epoch)
    }

    /// Optional-preserving overload: `nil` in, `nil` out (nothing to count from).
    nonisolated static func countFrom(_ date: Date?) -> Date? {
        date.map(countFrom)
    }

    // MARK: - Persistence (writes go through SchoolYearStore)

    nonisolated static func setEpoch(_ date: Date?) {
        let defaults = UserDefaults.standard
        guard let date else {
            defaults.removeObject(forKey: UserDefaultsKeys.schoolYearCounterEpoch)
            return
        }
        defaults.set(date.timeIntervalSinceReferenceDate, forKey: UserDefaultsKeys.schoolYearCounterEpoch)
    }
}
