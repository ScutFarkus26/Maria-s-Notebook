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
// The epoch is not stored. When counters reset at the year start it *is* the first day of
// the school year containing today, worked out from the (synced) start date, so it moves on
// its own when a new year begins or the start date is edited. It used to be a stored date,
// and a dismissed new-year prompt left it on the previous year's first day.
//
// Nothing is written or deleted — the underlying dates are untouched, and switching to
// "All history" (Settings → School year) restores the unclamped behavior exactly.
//
// Reads are `nonisolated static` so the off-main aging engines can use them the same way
// `FloridaGradeCalculator` reads the school-year start. `SchoolYearStore` owns the writes.

import Foundation

enum SchoolYearCounters {
    /// The day counters count from, or nil when they count the full history.
    nonisolated static var epoch: Date? {
        isResetting ? YearPlanStaleness.currentYearStart() : nil
    }

    /// True when counters restart at the school-year start rather than running from all history.
    nonisolated static var isResetting: Bool { isResetting(in: .standard) }

    /// The mode as `defaults` holds it. Before the mode had its own key, a stored epoch date
    /// meant "reset", so that date still stands in for the mode until the key is written.
    nonisolated static func isResetting(in defaults: UserDefaults) -> Bool {
        if let mode = defaults.object(forKey: UserDefaultsKeys.schoolYearCountersResetAtYearStart) as? Bool {
            return mode
        }
        return defaults.object(forKey: UserDefaultsKeys.schoolYearCounterEpoch) != nil
    }

    /// True once the mode has its own key (written by `setResetting`, a sync, or a restore).
    nonisolated static func hasExplicitMode(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: UserDefaultsKeys.schoolYearCountersResetAtYearStart) is Bool
    }

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

    nonisolated static func setResetting(_ resetting: Bool, defaults: UserDefaults = .standard) {
        defaults.set(resetting, forKey: UserDefaultsKeys.schoolYearCountersResetAtYearStart)
    }
}
