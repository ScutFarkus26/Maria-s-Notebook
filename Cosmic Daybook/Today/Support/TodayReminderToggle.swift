// TodayReminderToggle.swift
// A tap on one of Today's reminders, by the state its row was drawn with.

import Foundation

/// Today's reminder rows are the `CDReminder` objects the Reminders sync
/// changes in place, and a row isn't redrawn the moment they change. The
/// tap used to flip whatever the reminder held then, so one ticked in Apple
/// Reminders but still drawn open was reopened, and the reopening written
/// back to Reminders (bug hunt 2026-11-03 #48). It now does what the row
/// showed: a row drawn open completes, a row drawn done reopens.
enum TodayReminderToggle {
    /// Completes `reminder` when its row was drawn open, reopens it when drawn
    /// done. Returns false, changing nothing, when it is already that way.
    @discardableResult
    static func apply(to reminder: CDReminder, drawnCompleted: Bool) -> Bool {
        let completes = !drawnCompleted
        guard reminder.isCompleted != completes else { return false }
        if completes {
            reminder.markCompleted()
        } else {
            reminder.markIncomplete()
        }
        return true
    }
}
