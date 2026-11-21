// WorkLogService+Parts.swift
// One child's finish on a row several children share, and the check-in a log
// is the doing of. Split from WorkLogService.swift for SwiftLint's length limits.

import CoreData
import Foundation

extension WorkLogService {

    // MARK: - One child's part

    /// What `finishPart` did.
    struct PartFinished {
        /// False when her part was already finished: nothing was written.
        let recorded: Bool
        /// True when hers was the last part open, so the row closed.
        let closedRow: Bool
    }

    /// One child has finished her part of a row several children share
    /// (project and book-club work): her participant row is stamped and her
    /// completion written, and the row stays open for the others. When hers
    /// was the last part open, the row closes through `log`, as `status`, so
    /// the day's check-in, the later ones and the linked todos are settled
    /// like any other close. Claude's `completed_by` used to stamp one child
    /// at a time and never close the row, so a project finished child by
    /// child read Working for good (domain logic review 2026-11-20, R23).
    ///
    /// For a row that is hers alone (her own copy, or the only child on it),
    /// log a closing status instead. Doesn't save.
    @discardableResult
    static func finishPart(
        of work: CDWorkModel,
        for studentID: UUID,
        on day: Date = Date(),
        note: String = "",
        closingAs status: WorkStatus = .done,
        context: NSManagedObjectContext
    ) throws -> PartFinished {
        let finishDay = min(AppCalendar.startOfDay(day), AppCalendar.startOfDay(Date()))
        var participant = work.participant(for: studentID)
        guard participant?.completedAt == nil else { return PartFinished(recorded: false, closedRow: false) }
        if participant == nil {
            // An owner with no participant row of her own still gets her finish kept.
            let made = CDWorkParticipantEntity(context: context)
            made.id = UUID()
            made.studentID = studentID.uuidString
            made.work = work
            participant = made
        }
        participant?.completedAt = finishDay
        if let workID = work.id {
            _ = try WorkCompletionService.markCompleted(
                workID: workID, studentID: studentID, note: note, at: finishDay,
                in: context, saveImmediately: false
            )
        }
        guard work.status.isOpen, partsStillOpen(on: work).isEmpty else {
            return PartFinished(recorded: true, closedRow: false)
        }
        try log(
            [.init(work: work, status: status.isClosed ? status : .done)],
            on: finishDay, context: context, saveImmediately: false
        )
        return PartFinished(recorded: true, closedRow: true)
    }

    /// The children named on `work` whose part isn't finished: a participant
    /// with no finish, and an owner with no participant row at all. The Work
    /// column's own reading (`QuietStudentsOrder.openStudentIDs`), so "the
    /// last child" here is the last child that column shows it open for.
    static func partsStillOpen(on work: CDWorkModel) -> Set<UUID> {
        QuietStudentsOrder.openStudentIDs(of: work)
    }

    // MARK: - The checked check-in

    /// Moves the check-in a log is the doing of (`log`'s `checked`) to the
    /// moment of the log, so it is settled with the rest and the calendar
    /// shows the day it was checked. Nil, changing nothing, for a check-in
    /// that isn't scheduled any more.
    ///
    /// A due date on the day it leaves is an older build's copy of that day,
    /// and goes with it (`WorkCheckInService.releaseDueDate`); left behind, a
    /// check done early asked for the guide once more on the old day, as if a
    /// due date had come (domain logic Phase 10, cold review finding 7). A
    /// Due Date check's day is the guide's own due date, so it stays.
    static func moveChecked(_ checkIn: CDWorkCheckIn, to when: Date) -> MovedCheckIn? {
        guard checkIn.status == .scheduled, !checkIn.isDeleted else { return nil }
        let work = checkIn.work
        let dueBefore = work?.dueAt
        let planned = checkIn.date
        checkIn.date = when
        if let work, !WorkCheckInService.isDueDateCheck(checkIn) {
            WorkCheckInService.releaseDueDate(of: work, followingCheckOn: planned)
        }
        return MovedCheckIn(
            objectID: checkIn.objectID, from: planned, to: when,
            dueAt: work?.dueAt != dueBefore ? MovedDueDate(from: dueBefore, to: work?.dueAt) : nil
        )
    }

    /// Undo's half: the checked check-in goes back to the day it was planned
    /// for, unless the guide has moved or marked it since, and a due date it
    /// let go of or carried comes back unless the guide has changed it since.
    static func restoreChecked(_ moved: MovedCheckIn?, in context: NSManagedObjectContext) {
        guard let moved,
              let checkIn = context.existing(CDWorkCheckIn.self, moved.objectID),
              checkIn.status == .scheduled, checkIn.date == moved.to else { return }
        checkIn.date = moved.from
        if let due = moved.dueAt, let work = checkIn.work, work.dueAt == due.to {
            work.dueAt = due.from
        }
    }
}
