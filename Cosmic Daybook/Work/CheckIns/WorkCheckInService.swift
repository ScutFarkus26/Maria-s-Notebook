// WorkCheckInService.swift
// Small persistence service for CDWorkCheckIn operations to keep model methods side-effect free.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import CoreData

/// A small service that centralizes persistence for CDWorkCheckIn operations.
///
/// This service ensures that model methods remain free of side-effects
/// (no implicit saves), while callers can perform explicit, transactional
/// operations that throw on failure.
/// This file includes only structural and documentation improvements; behavior is unchanged.
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
}
