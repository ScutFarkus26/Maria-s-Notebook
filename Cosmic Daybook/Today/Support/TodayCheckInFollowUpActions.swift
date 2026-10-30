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
    ///
    /// The day she presents a report to the class is the exception
    /// (2026-10-30): done means she presented it, so the report and its
    /// linked copies move to Presented and close as Finished.
    static func markCheckedIn(
        _ item: WorkCheckInFollowUp,
        at now: Date = Date(),
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator? = nil
    ) throws {
        let checkIn = item.checkIn
        let dueDate = checkIn.date
        // Takes back the report's stage ticks too, if the log doesn't save.
        let transaction = ContextMutationTransaction(context: context)
        checkIn.date = now
        let entries = presentedEntries(for: item, at: now, context: context) ?? [.init(work: item.work)]
        do {
            try WorkLogService.log(entries, on: now, context: context, saveCoordinator: saveCoordinator)
        } catch {
            transaction.rollback()
            checkIn.date = dueDate
            throw error
        }
        transaction.commit()
    }

    /// For the day she presents an open report: every moving copy at its
    /// last stage, and the closes to log. Nil for any other check-in.
    private static func presentedEntries(
        for item: WorkCheckInFollowUp, at now: Date, context: NSManagedObjectContext
    ) -> [WorkLogService.Entry]? {
        let report = item.work
        guard ReportStages.isReport(report), ReportStages.isPresentDay(item.checkIn), report.status.isOpen else {
            return nil
        }
        let last = ReportStages.titles(of: report).count - 1
        let entries = ReportStages.set(
            stage: last, on: ReportStages.movingCopies(of: report, in: context), day: now, context: context
        )
        return entries.isEmpty ? nil : entries
    }
}
