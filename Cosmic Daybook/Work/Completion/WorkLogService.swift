// WorkLogService.swift
// Logging a work check — the one write that changes a work row's status.
//
// A work item is one child's row. Before this service, five screens set
// `status` on their own, three of them without the repository, none of them
// touched the row's check-ins, and the "N Students" sheet on the Scheduled
// strip could not change a status at all. Now every status change is a log
// entry: the row takes its status, a closing status stamps `completedAt` and
// writes a `CDWorkCompletionRecord`, the day's check-in is marked completed
// (which is what takes the pill off the Scheduled strip), later check-ins on
// a closed row are skipped, any note lands on the row as a dated note, and
// the open todos linked to the row are completed (`linkedWorkItemID`). The
// whole thing hands back a token the caller can Undo with.
//
// A log happens today or earlier. A pill on a later day of the week used to
// log on its own day: Mastered on Thursday's pill on Monday dated the
// completion and the note Thursday, and completed Tuesday's and Wednesday's
// check-ins too (bug hunt 2026-10-12 #37). A later day is logged as today.
//
// "The check happened" is a log too (domain logic review 2026-11-20, R11):
// Done on Today, Done on the work page and Claude's `complete_check_in_on`
// all pass the check-in as `checked`, with a "seen, unchanged" entry. It is
// dated the day it was checked (never later than today), and every earlier
// check-in still waiting is settled with it. The work page and Claude used to
// mark that one check-in alone, so Monday's missed check stayed overdue.
//
// One child's finish on a row several children share is `finishPart`; the
// last child's finish closes the row here (R23).

import CoreData
import Foundation

enum WorkLogService {

    /// One row's line in the log.
    struct Entry {
        let work: CDWorkModel
        /// The status to set. `nil` means "seen, unchanged": the check-in is
        /// still marked completed, because the check happened.
        let status: WorkStatus?
        let note: String?

        init(work: CDWorkModel, status: WorkStatus? = nil, note: String? = nil) {
            self.work = work
            self.status = status
            self.note = note
        }
    }

    /// Each description is shown as is (toasts on Today, the week plan and
    /// the work agenda; MCP returns it too).
    enum LogError: LocalizedError {
        case nothingToLog
        case saveFailed
        case undoSaveFailed
        case undoUnavailable

        var errorDescription: String? {
            switch self {
            case .nothingToLog: return "There is no work to log."
            case .saveFailed: return "Couldn't save that work check. Try again."
            case .undoSaveFailed: return "Couldn't undo that. Try again."
            case .undoUnavailable: return "That work check can no longer be undone."
            }
        }
    }

    /// What one call did, plus the token that reverses it.
    struct Receipt {
        let token: UndoToken
        let rows: Int
        let closed: Int
        let reopened: Int
        /// Check-ins marked completed or skipped — the pills that left the strip.
        let checkInsSettled: Int
    }

    // MARK: - Log

    /// Applies every entry, settles the rows' check-ins for `day`, and saves
    /// once. On a failed save the in-memory changes are reverted before the
    /// error is thrown, so nothing half-logged is left in the context.
    ///
    /// `day` may be in the past (a check logged late); a day after today is
    /// logged as today, since nothing has happened on it yet.
    ///
    /// - Parameter checked: the check-in this log is the doing of (Done on a
    ///   check-in row). It moves to the moment of the log, `day` or now if
    ///   `day` is still to come, so the calendar shows the day it was
    ///   checked, and is settled with the rest. Undo puts it back.
    @discardableResult
    static func log(
        _ entries: [Entry],
        on day: Date = Date(),
        checked: CDWorkCheckIn? = nil,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator? = nil,
        saveImmediately: Bool = true
    ) throws -> Receipt {
        guard !entries.isEmpty else { throw LogError.nothingToLog }
        let now = Date()
        let logDay = min(AppCalendar.startOfDay(day), AppCalendar.startOfDay(now))

        context.processPendingChanges()
        let insertedBefore = context.insertedObjects
        var token = UndoToken(day: logDay)
        token.checkedCheckIn = checked.flatMap { moveChecked($0, to: min(day, now)) }
        var closed = 0
        var reopened = 0
        var settled = 0

        for entry in entries {
            let work = entry.work
            token.rows.append(RowSnapshot(work))
            let previous = work.status
            let students = studentsLogged(on: work, in: context)

            if let status = entry.status, status != previous {
                work.status = status
                if status.isClosed {
                    closed += 1
                    token.participants += close(work, for: students, on: logDay, in: context)
                } else if previous.isClosed {
                    reopened += 1
                    reopen(work, for: students, token: &token)
                }
            }
            work.lastTouchedAt = now
            // The work has been seen, so the follow-ups about it are done.
            if let workID = work.id {
                let completed = TodoCompletionService.completeTodosLinked(toWork: workID, in: context)
                token.completedTodos += completed.map(\.objectID)
            }
            settled += settleCheckIns(of: work, on: logDay, closing: work.status.isClosed, token: &token, in: context)
            if let note = entry.note?.trimmed(), !note.isEmpty {
                addNote(note, to: work, for: students, on: logDay, in: context)
            }
        }

        context.processPendingChanges()
        let created = Array(context.insertedObjects.subtracting(insertedBefore))
        try? context.obtainPermanentIDs(for: created)
        token.createdObjectIDs = created.map(\.objectID)

        if saveImmediately {
            // Every caller shows `LogError.saveFailed` itself, so the global alert stays quiet.
            let saved = saveCoordinator?.save(context, reason: "Log work check", alertOnFailure: false)
                ?? context.safeSave()
            guard saved else {
                revert(token, in: context)
                throw LogError.saveFailed
            }
        }
        return Receipt(token: token, rows: entries.count, closed: closed, reopened: reopened, checkInsSettled: settled)
    }

    // MARK: - Pieces

    /// Whom a row's log line is about. A linked copy is one child's row, even
    /// though it names her peers; a genuinely shared row (project or
    /// book-club work) is about everyone on it. A check-in's note is scoped
    /// the same way (`CDWorkCheckIn.setLegacyNoteText`).
    static func studentsLogged(on work: CDWorkModel, in context: NSManagedObjectContext) -> [UUID] {
        let named = WorkGrouping.studentIDs(of: work)
        if named.count > 1, WorkOwnership.isShared(work, in: context) { return named }
        return WorkGrouping.owner(of: work).map { [$0] } ?? []
    }

    /// Stamps the row and the participant rows of the children logged, and
    /// writes one completion record per child logged. A linked copy's other
    /// participants are classmates with rows of their own, so they are left
    /// alone; `reopen` clears the same children. Returns the participant
    /// snapshots for the undo token.
    ///
    /// The records carry no note: the log's note is the dated work note
    /// `addNote` files. Both used to be written, so a closing note showed
    /// twice on the child's Notes tab, in Observations and in chat context
    /// (bug hunt 2026-10-12 #36).
    private static func close(
        _ work: CDWorkModel, for students: [UUID], on day: Date, in context: NSManagedObjectContext
    ) -> [ParticipantSnapshot] {
        work.completedAt = day
        var snapshots: [ParticipantSnapshot] = []
        // A child whose part was finished earlier (`finishPart`) has her
        // completion record already; the close writes one for the rest.
        var finishedEarlier = Set<UUID>()
        for participant in participants(of: work, among: students) {
            snapshots.append(ParticipantSnapshot(participant))
            if participant.completedAt == nil {
                participant.completedAt = day
            } else if let id = UUID(uuidString: participant.studentID) {
                finishedEarlier.insert(id)
            }
        }
        guard let workID = work.id else { return snapshots }
        for studentID in students where !finishedEarlier.contains(studentID) {
            _ = try? WorkCompletionService.markCompleted(
                workID: workID, studentID: studentID, at: day, in: context, saveImmediately: false
            )
        }
        return snapshots
    }

    /// Clears the row and the participant rows `close` stamps: the children logged.
    private static func reopen(_ work: CDWorkModel, for students: [UUID], token: inout UndoToken) {
        work.completedAt = nil
        for participant in participants(of: work, among: students) {
            token.participants.append(ParticipantSnapshot(participant))
            participant.completedAt = nil
        }
    }

    /// The participant rows of `students`, or every one when the row names
    /// no child to log (unclaimed project work).
    private static func participants(of work: CDWorkModel, among students: [UUID]) -> [CDWorkParticipantEntity] {
        guard !students.isEmpty else { return participants(of: work) }
        let wanted = Set(students)
        return participants(of: work).filter { UUID(uuidString: $0.studentID).map(wanted.contains) ?? false }
    }

    /// Check-ins on or before `day` happened, so they are completed; later
    /// ones on a row that just closed will never happen, so they are skipped.
    /// Dates are kept — a skipped check-in stays on the day it was planned for.
    private static func settleCheckIns(
        of work: CDWorkModel, on day: Date, closing: Bool, token: inout UndoToken, in context: NSManagedObjectContext
    ) -> Int {
        var settled = 0
        for checkIn in scheduledCheckIns(of: work, in: context) {
            guard let date = checkIn.date else { continue }
            let checkDay = AppCalendar.startOfDay(date)
            if checkDay <= day {
                token.checkIns.append(CheckInSnapshot(checkIn))
                checkIn.status = .completed
                settled += 1
            } else if closing {
                token.checkIns.append(CheckInSnapshot(checkIn))
                checkIn.status = .skipped
                settled += 1
            }
        }
        return settled
    }

    /// A dated note on the row, scoped to its child (or children, on a shared
    /// row), and on the day's check-in when there is one, so it reads under
    /// either. The work editor files a note without a status change through
    /// this door too.
    static func addNote(_ body: String, to work: CDWorkModel, on day: Date, in context: NSManagedObjectContext) {
        addNote(body, to: work, for: studentsLogged(on: work, in: context), on: day, in: context)
    }

    private static func addNote(
        _ body: String, to work: CDWorkModel, for students: [UUID], on day: Date, in context: NSManagedObjectContext
    ) {
        let note = CDNote(context: context)
        note.body = body
        if students.count == 1, let only = students.first {
            note.scope = .student(only)
        } else if students.count > 1 {
            note.scope = .students(students)
        } else {
            note.scope = .all
        }
        note.lessonID = work.lessonID
        note.work = work
        if !AppCalendar.shared.isDateInToday(day) {
            note.createdAt = day
        }
        note.workCheckIn = checkIns(of: work, in: context).first { checkIn in
            guard let date = checkIn.date else { return false }
            return AppCalendar.shared.isDate(date, inSameDayAs: day)
        }
        note.syncStudentLinks(in: context)
    }

    // MARK: - Lookups

    static func participants(of work: CDWorkModel) -> [CDWorkParticipantEntity] {
        (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
    }

    /// Every check-in that names this work — by relationship or by the
    /// `workID` string older creation paths wrote alone.
    static func checkIns(of work: CDWorkModel, in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        guard let id = work.id?.uuidString, !id.isEmpty else { return [] }
        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = NSPredicate(format: "workID == %@ OR work == %@", id, work)
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    static func scheduledCheckIns(of work: CDWorkModel, in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        checkIns(of: work, in: context).filter { $0.status == .scheduled }
    }
}

// MARK: - Targets

/// Which rows a "log this work" gesture means.
enum WorkLogTargets {

    enum TargetError: LocalizedError {
        /// A shared row (project or book-club work) is one row for everyone
        /// on it; it cannot take a status for some of them.
        case sharedRowNeedsEveryone(childCount: Int)
        case noneOfThoseChildren

        var errorDescription: String? {
            switch self {
            case .sharedRowNeedsEveryone(let count):
                return "This work is one shared row for \(count) children; log it for everyone, "
                    + "or record one child with completed_by."
            case .noneOfThoseChildren:
                return "None of those children has a row on this work."
            }
        }
    }

    /// `students == nil` means everyone: every linked copy of the row whose
    /// child is still in the class, and the row itself whoever's it is. A
    /// copy belonging to a child who has left (`CDStudent.hasLeft(by:)`) is
    /// her record and stays as she left it (domain logic review R7). A set
    /// narrows it to the copies those children own.
    static func resolve(
        work: CDWorkModel, students: Set<UUID>? = nil, in context: NSManagedObjectContext, now: Date = Date()
    ) throws -> [CDWorkModel] {
        let group = WorkGrouping.group(containing: work, in: context)
        guard let students else {
            return group.members.filter { $0 === work || !ownerHasLeft($0, by: now, in: context) }
        }
        if case .shared(let count) = group.shape {
            guard Set(group.studentIDs).isSubset(of: students) else {
                throw TargetError.sharedRowNeedsEveryone(childCount: count)
            }
            return group.members
        }
        let rows = group.members.filter { row in
            WorkGrouping.owner(of: row).map(students.contains) ?? false
        }
        guard !rows.isEmpty else { throw TargetError.noneOfThoseChildren }
        return rows
    }

    /// Whether the row's owner is on file and had left the class by `day`.
    /// A row whose child can't be found counts as still hers to log.
    private static func ownerHasLeft(_ work: CDWorkModel, by day: Date, in context: NSManagedObjectContext) -> Bool {
        guard let owner = WorkGrouping.owner(of: work),
              let student = context.object(CDStudent.self, id: owner) else { return false }
        return student.hasLeft(by: day)
    }
}
