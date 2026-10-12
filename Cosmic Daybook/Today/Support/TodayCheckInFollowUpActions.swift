// TodayCheckInFollowUpActions.swift
// The write behind a due check-in row's "Mark checked in", out of the view so
// it can be tested without one.

import CoreData
import Foundation

enum TodayCheckInFollowUpActions {

    /// Marks the row's work as checked: a "seen, unchanged" line through
    /// `WorkLogService`, the one writer of work checks, so every check-in due
    /// by today is settled (not only the row's earliest), the work is stamped
    /// as seen (`lastTouchedAt`, which Gone quiet reads), its linked todos
    /// close, and a failed save is reverted before the error is thrown
    /// (bug hunt 2026-10-12, #51).
    ///
    /// Done means "checked today": the row's own check-in moves to now, so the
    /// work calendar shows the day it was checked, not the day it was due —
    /// the rule `WorkCheckInService.markCompleted` kept, kept deliberately.
    /// Later overdue check-ins keep their days, as a log from the week strip
    /// leaves them.
    static func markCheckedIn(
        _ item: WorkCheckInFollowUp,
        at now: Date = Date(),
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator? = nil
    ) throws {
        let checkIn = item.checkIn
        let dueDate = checkIn.date
        checkIn.date = now
        do {
            try WorkLogService.log(
                [.init(work: item.work)], on: now, context: context, saveCoordinator: saveCoordinator
            )
        } catch {
            checkIn.date = dueDate
            throw error
        }
    }
}
