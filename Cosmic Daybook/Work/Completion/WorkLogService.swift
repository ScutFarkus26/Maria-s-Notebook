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
// a closed row are skipped, and any note lands on the row as a dated note.
// The whole thing hands back a token the caller can Undo with.

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

    enum LogError: LocalizedError {
        case nothingToLog
        case saveFailed(String)
        case undoUnavailable

        var errorDescription: String? {
            switch self {
            case .nothingToLog: return "There is no work to log."
            case .saveFailed(let message): return message
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
    @discardableResult
    static func log(
        _ entries: [Entry],
        on day: Date = Date(),
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator? = nil,
        saveImmediately: Bool = true
    ) throws -> Receipt {
        guard !entries.isEmpty else { throw LogError.nothingToLog }
        let logDay = AppCalendar.startOfDay(day)
        let now = Date()

        context.processPendingChanges()
        let insertedBefore = context.insertedObjects
        var token = UndoToken(day: logDay)
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
                    token.participants += close(work, for: students, on: logDay, note: entry.note, in: context)
                } else if previous.isClosed {
                    reopened += 1
                    reopen(work, token: &token)
                }
            }
            work.lastTouchedAt = now
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
            let saved = saveCoordinator?.save(context, reason: "Log work check") ?? context.safeSave()
            guard saved else {
                revert(token, in: context)
                throw LogError.saveFailed(saveCoordinator?.lastSaveErrorMessage ?? "The work check could not be saved.")
            }
        }
        return Receipt(token: token, rows: entries.count, closed: closed, reopened: reopened, checkInsSettled: settled)
    }

    // MARK: - Pieces

    /// Whom a row's log line is about. A linked copy is one child's row, even
    /// though it names her peers; a genuinely shared row (project or
    /// book-club work) is about everyone on it.
    private static func studentsLogged(on work: CDWorkModel, in context: NSManagedObjectContext) -> [UUID] {
        let group = WorkGrouping.group(containing: work, in: context)
        if case .shared = group.shape { return group.studentIDs }
        return WorkGrouping.owner(of: work).map { [$0] } ?? []
    }

    /// Stamps the row and its participants and writes one completion record
    /// per child logged. Returns the participant snapshots for the undo token.
    private static func close(
        _ work: CDWorkModel, for students: [UUID], on day: Date, note: String?, in context: NSManagedObjectContext
    ) -> [ParticipantSnapshot] {
        work.completedAt = day
        var snapshots: [ParticipantSnapshot] = []
        for participant in participants(of: work) {
            snapshots.append(ParticipantSnapshot(participant))
            if participant.completedAt == nil { participant.completedAt = day }
        }
        guard let workID = work.id else { return snapshots }
        for studentID in students {
            _ = try? WorkCompletionService.markCompleted(
                workID: workID, studentID: studentID, note: note ?? "", at: day,
                in: context, saveImmediately: false
            )
        }
        return snapshots
    }

    private static func reopen(_ work: CDWorkModel, token: inout UndoToken) {
        work.completedAt = nil
        guard let owner = WorkGrouping.owner(of: work), let participant = work.participant(for: owner) else { return }
        token.participants.append(ParticipantSnapshot(participant))
        participant.completedAt = nil
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

    /// `students == nil` means everyone: every linked copy of the row. A set
    /// narrows it to the copies those children own.
    static func resolve(
        work: CDWorkModel, students: Set<UUID>? = nil, in context: NSManagedObjectContext
    ) throws -> [CDWorkModel] {
        let group = WorkGrouping.group(containing: work, in: context)
        guard let students else { return group.members }
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
}
