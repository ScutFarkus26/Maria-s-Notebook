// WorkCheckInService.swift
// Small persistence service for CDWorkCheckIn operations to keep model methods side-effect free.
// Also the one place a linked copy's check-in moves with its group's, and the
// one way a scheduled check-in comes off the calendar.

import Foundation
import CoreData

/// A small service that centralizes persistence for CDWorkCheckIn operations.
///
/// This service ensures that model methods remain free of side-effects
/// (no implicit saves), while callers can perform explicit, transactional
/// operations that throw on failure.
struct WorkCheckInService {
    let context: NSManagedObjectContext

    // MARK: - Creation

    /// Create and insert a new check-in for the given work.
    /// - Returns: The newly created CDWorkCheckIn.
    @discardableResult
    func createCheckIn(for work: CDWorkModel,
                       date: Date,
                       status: WorkCheckInStatus = .scheduled,
                       purpose: String = "",
                       note: String = "") throws -> CDWorkCheckIn {
        let trimmedNote = note.trimmed()
        let ci = CDWorkCheckIn.make(for: work, on: date, purpose: purpose, status: status, in: context)
        if !trimmedNote.isEmpty {
            ci.setLegacyNoteText(trimmedNote, in: context)
        }
        return ci
    }

    // MARK: - Updates

    /// Mark a check-in as completed, and complete the open todos linked to
    /// its work: the check-in is the follow-up they were about. Does not save.
    func markCompleted(_ checkIn: CDWorkCheckIn, note: String? = nil, at date: Date = Date()) throws {
        checkIn.status = .completed
        checkIn.date = date
        if let note {
            checkIn.setLegacyNoteText(note, in: context)
        }
        if let workID = checkIn.work?.id ?? UUID(uuidString: checkIn.workID) {
            TodoCompletionService.completeTodosLinked(toWork: workID, in: context)
        }
    }

    /// Puts a work item on `day` to be checked: its earliest check-in still
    /// marked Scheduled moves there, or one is made, and the due date follows
    /// so the two never drift. The Work grid's Schedule and a child's overview
    /// card both write through here. Does not save.
    ///
    /// A finished check-in, and the note on it, stays on the day it happened.
    /// Open work usually carries one — logging "keep working" completes that
    /// day's — and taking the earliest of any status moved it to the new day,
    /// rewriting history and leaving nothing new on the calendar.
    @discardableResult
    func scheduleCheck(for work: CDWorkModel, on day: Date) -> CDWorkCheckIn {
        let checkDay = AppCalendar.startOfDay(day)
        work.dueAt = checkDay
        let earliest = WorkLogService.scheduledCheckIns(of: work, in: context).min { lhs, rhs in
            let lhsDate = lhs.date ?? .distantFuture
            let rhsDate = rhs.date ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
        guard let earliest else {
            return CDWorkCheckIn.make(
                for: work, on: checkDay, purpose: CheckInReason.progressCheck.rawValue, in: context
            )
        }
        earliest.date = checkDay
        if earliest.work == nil { earliest.work = work }
        return earliest
    }

    /// Reschedule a check-in and persist immediately.
    func reschedule(_ checkIn: CDWorkCheckIn, to date: Date, note: String? = nil) throws {
        checkIn.date = date
        checkIn.status = .scheduled
        if let note {
            checkIn.setLegacyNoteText(note, in: context)
        }
    }

    // MARK: - Lookup

    /// Every check-in of `work` on `day`, through the relationship and the
    /// `workID` string both.
    func checkIns(of work: CDWorkModel, on day: Date) -> [CDWorkCheckIn] {
        WorkDeletionService.checkIns(of: work, in: context).filter { checkIn in
            guard let date = checkIn.date else { return false }
            return AppCalendar.isSameDay(date, day)
        }
    }

    /// A check-in on `day` that another would duplicate: scheduled or
    /// completed. A skipped one doesn't count — putting the day back is a
    /// fresh decision. `excluding` is the check-in on its way there.
    func blockingCheckIn(of work: CDWorkModel, on day: Date, excluding: CDWorkCheckIn? = nil) -> CDWorkCheckIn? {
        checkIns(of: work, on: day).first { $0.status != .skipped && $0 !== excluding }
    }

    /// A work row whose child is on file but no longer enrolled. A row whose
    /// child can't be found is treated as hers, since nothing says she left.
    func ownerHasLeft(_ work: CDWorkModel) -> Bool {
        guard let owner = WorkGrouping.owner(of: work),
              let student = StudentRepository(context: context).fetchStudent(id: owner) else { return false }
        return !student.isEnrolled
    }

    // MARK: - Moving a linked copy's check-in

    /// What happened to a linked copy's check-in when its group's moved.
    enum SiblingMove {
        /// Its check-in on the old day moved to the new one.
        case moved(CDWorkCheckIn)
        /// Its child has left the classroom, so the check-in stayed.
        case childHasLeft(CDWorkCheckIn)
        /// It already has a check-in on the new day (`existing`), so this one
        /// stayed. The caller decides what that means: update_work reports it;
        /// Move All Forward folds the two into one.
        case blocked(CDWorkCheckIn, existing: CDWorkCheckIn)
        /// Its check-in on the old day was already completed or skipped.
        case settled(WorkCheckInStatus)
        /// It had nothing on the old day.
        case noneOnDay
    }

    /// Moves `sibling`'s check-in on `fromDay` to `landing`, as its group's
    /// own check-in moved: the one decision about the group reconsidered, so
    /// every child's copy goes with it. Never leaves two check-ins on one day,
    /// and leaves a departed child's copy where it is. update_work's
    /// `move_check_in_from` and Move All Forward both move linked copies
    /// through here. Does not save.
    func moveSiblingCheckIn(of sibling: CDWorkModel, from fromDay: Date, to landing: Date) -> SiblingMove {
        let onDay = checkIns(of: sibling, on: fromDay)
        guard let scheduled = onDay.first(where: { $0.status == .scheduled }) else {
            return onDay.first.map { .settled($0.status) } ?? .noneOnDay
        }
        if ownerHasLeft(sibling) { return .childHasLeft(scheduled) }
        if let existing = blockingCheckIn(of: sibling, on: landing, excluding: scheduled) {
            return .blocked(scheduled, existing: existing)
        }
        Self.move(scheduled, toDay: landing)
        return .moved(scheduled)
    }

    /// Only the day changes. The time of day is kept, as the Today view's
    /// "bump to tomorrow" keeps it, so the row's place in the day's ordering
    /// stays where it was; purpose, status and notes are not touched.
    static func move(_ checkIn: CDWorkCheckIn, toDay day: Date) {
        let calendar = AppCalendar.shared
        let time = calendar.dateComponents([.hour, .minute, .second], from: checkIn.date ?? day)
        checkIn.date = calendar.date(
            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day
        ) ?? day
    }

    // MARK: - Unscheduling

    /// A check-in as it was before `unschedule` removed it, so Undo can put
    /// the same record back.
    struct RemovedCheckIn {
        let id: UUID?
        let workID: String
        let work: NSManagedObjectID?
        let date: Date?
        let statusRaw: String
        let purpose: String
        let studentInitiated: Bool
    }

    /// What `unschedule` did with a check-in, enough for Undo.
    enum Unscheduled {
        /// It had no note and was deleted; this is what it was.
        case removed(RemovedCheckIn)
        /// It carries a note, so it was marked skipped where it was, note and
        /// all, rather than deleted.
        case skipped(NSManagedObjectID)
    }

    /// Whether a check-in carries a note of its own: one typed on the check.
    /// A note logged on the work that day is linked to the check too, but it
    /// is the work's (`note.work`), and deleting the check leaves it on the
    /// work (`CDWorkCheckIn.prepareForDeletion`), so it doesn't count.
    static func hasNote(_ checkIn: CDWorkCheckIn) -> Bool {
        ((checkIn.notes as? Set<CDNote>) ?? []).contains { !$0.isDeleted && $0.work == nil }
    }

    /// Takes a scheduled check-in off the calendar, so its work goes back to
    /// To Schedule. One carrying a note is marked skipped where it was, since
    /// deleting it would lose the note; one with none is deleted, and what it
    /// was comes back for Undo. A check-in that isn't scheduled is history and
    /// is never touched (nil). The work's due date is the caller's to reset,
    /// once every check-in it is clearing has gone. Does not save.
    @discardableResult
    func unschedule(_ checkIn: CDWorkCheckIn) -> Unscheduled? {
        guard checkIn.status == .scheduled, !checkIn.isDeleted else { return nil }
        if Self.hasNote(checkIn) {
            checkIn.status = .skipped
            return .skipped(checkIn.objectID)
        }
        let removed = RemovedCheckIn(
            id: checkIn.id,
            workID: checkIn.workID,
            work: checkIn.resolvedWork(in: context)?.objectID,
            date: checkIn.date,
            statusRaw: checkIn.statusRaw,
            purpose: checkIn.purpose,
            studentInitiated: checkIn.studentInitiated
        )
        context.delete(checkIn)
        return .removed(removed)
    }

    /// Puts a check-in `unschedule` skipped back on its day. False, changing
    /// nothing, when it is gone or no longer skipped (logged since, say).
    /// Does not save.
    @discardableResult
    func restoreSkipped(_ objectID: NSManagedObjectID) -> Bool {
        guard let checkIn = context.existing(CDWorkCheckIn.self, objectID), checkIn.status == .skipped else {
            return false
        }
        checkIn.status = .scheduled
        return true
    }

    /// Puts back a check-in `unschedule` removed: the same id, day, purpose
    /// and work. Nothing is made when a check-in with that id is back already
    /// (sync brought it, or Undo ran twice). Does not save.
    @discardableResult
    func restore(_ removed: RemovedCheckIn) -> CDWorkCheckIn? {
        if let id = removed.id, context.object(CDWorkCheckIn.self, id: id) != nil { return nil }
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.id = removed.id ?? UUID()
        checkIn.workID = removed.workID
        checkIn.date = removed.date
        checkIn.statusRaw = removed.statusRaw
        checkIn.purpose = removed.purpose
        checkIn.studentInitiated = removed.studentInitiated
        checkIn.work = removed.work.flatMap { context.existing(CDWorkModel.self, $0) }
        return checkIn
    }
}
