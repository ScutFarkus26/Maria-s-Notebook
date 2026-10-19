//
//  ChecklistCellRecords.swift
//  Cosmic Daybook
//
//  The record changes behind a cell's Mastered and Clear, shared by the cell
//  (its menu, card and keys) and the selection bar, so the two can't mean
//  different things again (bug hunt 2026-10-10, #41 and #42).
//
//  Mastered closes the child's work on the lesson. It used to look at open
//  work only and, finding none, made a second row and closed it, so a child
//  whose work was already closed got a duplicate.
//
//  Clear takes the child off the cell entirely: her plans and presentations
//  for the lesson, her work on it (open or finished), and its history and
//  mark, so the cell reads Ready again. The selection bar already took her off
//  finished work, cascading its notes away; the cell's own Clear left finished
//  work, so the cell still read Reviewing. Now both do the same.
//
//  What she wrote stays in her notes: notes on a presentation or a work row
//  that goes are taken off it first (both cascade), a note scoped to the whole
//  class (a work row's field note is) becomes hers so it doesn't turn up on
//  every child's page, and the text of a history row that goes (its notes and
//  follow-up note) is kept as a note on her, filed under the lesson. Because
//  Clear takes history away for good, the screens ask first when a cell holds
//  a given presentation, a mastery mark or finished work (`clearSummary`).
//
//  Neither saves; the caller owns the save.
//

import CoreData
import Foundation
import OSLog

enum ChecklistCellRecords {
    private static let logger = Logger.lessons

    // MARK: - Mastered

    /// The child's work on the lesson ends closed. Her open row closes as Done;
    /// with only closed rows, the newest stays as it is; a row is made (and
    /// closed) only when she has none.
    static func closeWorkForMastery(studentID: UUID, lessonID: UUID, in context: NSManagedObjectContext) {
        if let work = cellWork(studentID: studentID, lessonID: lessonID, in: context) {
            guard work.status.isOpen else { return }
            do {
                try WorkLogService.log([.init(work: work, status: .done)], context: context, saveImmediately: false)
            } catch {
                logger.warning("Couldn't close work for a mastery mark: \(error)")
            }
            return
        }
        do {
            let work = try WorkRepository(context: context).createWork(
                studentID: studentID, lessonID: lessonID, saveImmediately: false
            )
            try WorkLogService.log([.init(work: work, status: .done)], context: context, saveImmediately: false)
        } catch {
            logger.warning("Couldn't create work for a mastery mark: \(error)")
        }
    }

    /// The row a cell reads (`ClassGridEngine.cellWork`: open before
    /// closed, then newest), from the rows she owns when she owns any, so a
    /// linked copy that names her as a classmate is never closed in her place.
    static func cellWork(studentID: UUID, lessonID: UUID, in context: NSManagedObjectContext) -> CDWorkModel? {
        let rows = work(on: lessonID, involving: studentID, in: context)
        let owned = rows.filter { WorkGrouping.owner(of: $0) == studentID }
        return ClassGridEngine.cellWork(owned.isEmpty ? rows : owned)
    }

    // MARK: - Clear

    /// Takes the child off the cell: off the lesson's plans and presentations
    /// (a presentation she was alone on goes), off all its work (a row she was
    /// alone on goes), and her history rows and mastery mark for it go. Notes
    /// on what goes, and the history rows' text, stay in her notes.
    static func clear(studentID: UUID, lessonID: UUID, in context: NSManagedObjectContext) {
        let studentKey = studentID.uuidString
        let lessonKey = lessonID.uuidString

        // Every one of her history rows for the lesson goes below, some with their
        // presentation's cleanup, so their text is kept first.
        let historyRows = history(of: lessonKey, for: studentKey, in: context)
        for row in historyRows {
            keepText(of: row, for: studentID, lessonKey: lessonKey, in: context)
        }

        for assignment in presentations(of: lessonKey, naming: studentKey, in: context) {
            var remaining = assignment.studentIDs
            remaining.removeAll { $0 == studentKey }
            if remaining.isEmpty {
                for note in (assignment.unifiedNotes as? Set<CDNote>) ?? [] where !note.isDeleted {
                    note.lessonAssignment = nil
                    keep(note, for: studentID, lessonKey: lessonKey, in: context)
                }
                PresentationRecordCleanup.prepareToDelete(assignment, in: context)
                context.delete(assignment)
            } else {
                PresentationRecordCleanup.removeStudents([studentKey], from: assignment, in: context)
                assignment.studentIDs = remaining
            }
        }

        let rows = work(on: lessonID, involving: studentID, in: context)
        keepNotes(onRowsLeaving: rows, studentID: studentID, lessonKey: lessonKey, in: context)
        WorkDeletionService.removeWithoutSaving(studentID: studentID, from: rows, in: context)

        for row in historyRows where !row.isDeleted {
            context.delete(row)
        }
    }

    // MARK: - Asking first

    /// What clearing `cells` would take out of the children's history for good:
    /// presentations already given, mastery marks and finished work. Touches nothing.
    static func clearSummary(
        for cells: Set<CellIdentifier>, in context: NSManagedObjectContext
    ) -> ChecklistClearSummary {
        var summary = ChecklistClearSummary(cells: cells.count)
        for cell in cells {
            let studentKey = cell.studentID.uuidString
            let lessonKey = cell.lessonID.uuidString
            summary.givenPresentations += presentations(of: lessonKey, naming: studentKey, in: context)
                .filter(\.isPresented).count
            if history(of: lessonKey, for: studentKey, in: context)
                .contains(where: { $0.masteredAt != nil || $0.state == .proficient }) {
                summary.masteryMarks += 1
            }
            summary.finishedWork += work(on: cell.lessonID, involving: cell.studentID, in: context)
                .filter(\.status.isClosed).count
        }
        return summary
    }

    // MARK: - Pieces

    /// Every row of the lesson's work that names the child, as owner or participant.
    private static func work(
        on lessonID: UUID, involving studentID: UUID, in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        request.relationshipKeyPathsForPrefetching = ["participants"]
        return context.safeFetch(request).filter { !$0.isDeleted && WorkGrouping.involves(studentID, in: $0) }
    }

    /// The lesson's presentations that name the child.
    private static func presentations(
        of lessonKey: String, naming studentKey: String, in context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonKey)
        return context.safeFetch(request).filter { !$0.isDeleted && $0.studentIDs.contains(studentKey) }
    }

    /// The child's history rows for the lesson, mastery marks included.
    private static func history(
        of lessonKey: String, for studentKey: String, in context: NSManagedObjectContext
    ) -> [CDLessonPresentation] {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "studentID == %@ AND lessonID == %@", studentKey, lessonKey)
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    /// A note taken off a record that goes. One scoped to the whole class (a
    /// work row's field note is) becomes the child's: left as it was, it would
    /// show as a general note on every child's page. It is filed under the
    /// lesson when it named none, so it still says what it was about.
    private static func keep(
        _ note: CDNote, for studentID: UUID, lessonKey: String, in context: NSManagedObjectContext
    ) {
        if case .all = note.scope {
            note.scope = .student(studentID)
            note.syncStudentLinks(in: context)
        }
        if (note.lessonID ?? "").isEmpty { note.lessonID = lessonKey }
    }

    /// A history row's own text (its notes and follow-up note) kept as a note
    /// on the child before the row goes, dated when the row was.
    private static func keepText(
        of row: CDLessonPresentation, for studentID: UUID, lessonKey: String, in context: NSManagedObjectContext
    ) {
        let text = [row.notes, row.followUpNote]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !text.isEmpty else { return }
        let note = CDNote(context: context)
        note.body = text
        note.createdAt = row.presentedAt ?? row.createdAt ?? Date()
        note.updatedAt = note.createdAt
        note.scope = .student(studentID)
        note.lessonID = lessonKey
    }

    /// Notes on the rows taking her off will delete (rows she is alone on, or
    /// her own linked copy) are detached first, since the work's, its
    /// check-ins' and its completion records' notes cascade with it. They
    /// stay in her notes (`keep`).
    private static func keepNotes(
        onRowsLeaving rows: [CDWorkModel], studentID: UUID, lessonKey: String, in context: NSManagedObjectContext
    ) {
        let service = WorkDeletionService(context: context)
        var leaving: [CDWorkModel] = []
        for row in rows {
            do {
                let plan = try service.removalPlan(for: studentID, from: row)
                leaving += plan.steps.filter { $0.action == .deleteRow }.map(\.work)
            } catch WorkDeletionService.ServiceError.wouldEmptyRow {
                leaving.append(row)
            } catch {
                continue
            }
        }
        var seen = Set<NSManagedObjectID>()
        for row in leaving where seen.insert(row.objectID).inserted {
            for note in (row.unifiedNotes as? Set<CDNote>) ?? [] where !note.isDeleted {
                note.work = nil
                keep(note, for: studentID, lessonKey: lessonKey, in: context)
            }
            for checkIn in WorkDeletionService.checkIns(of: row, in: context) {
                for note in (checkIn.notes as? Set<CDNote>) ?? [] where !note.isDeleted {
                    note.workCheckIn = nil
                    keep(note, for: studentID, lessonKey: lessonKey, in: context)
                }
            }
            guard let workID = row.id?.uuidString else { continue }
            let records = CDFetchRequest(CDWorkCompletionRecord.self)
            records.predicate = NSPredicate(format: "workID == %@", workID)
            for record in context.safeFetch(records) {
                for note in (record.notes as? Set<CDNote>) ?? [] where !note.isDeleted {
                    note.workCompletionRecord = nil
                    keep(note, for: studentID, lessonKey: lessonKey, in: context)
                }
            }
        }
    }
}
