// StudentSequenceDetailLoader.swift
// Fetches the work / presentations / notes that StudentSequenceDetailSheet displays.
// Kept separate so the sheet view stays under SwiftLint length limits.

import Foundation
import CoreData

// MARK: - Detail row value types

struct WorkDetailItem: Identifiable {
    let id: UUID
    let title: String
    let lessonName: String
    let status: WorkStatus
    let kind: WorkKind?
    let assignedAt: Date?
}

struct PresentationDetailItem: Identifiable {
    let id: UUID
    let lessonName: String
    let presentedAt: Date?
    let notes: String
}

struct NoteDetailItem: Identifiable {
    let id: UUID
    let lessonName: String
    let body: String
    let createdAt: Date?
}

/// Aggregated payload returned by `StudentSequenceDetailLoader.load`.
struct StudentSequenceDetail {
    let work: [WorkDetailItem]
    let presentations: [PresentationDetailItem]
    let notes: [NoteDetailItem]
}

// MARK: - Loader

enum StudentSequenceDetailLoader {
    static func load(
        target: StudentSequenceDetailTarget,
        context: NSManagedObjectContext
    ) -> StudentSequenceDetail {
        let studentIDStr = target.studentID.uuidString
        let lessonIDStrs = target.lessonIDs.map(\.uuidString)

        let lessonMap = fetchLessonMap(lessonIDs: target.lessonIDs, context: context)
        let work = fetchWork(
            studentID: target.studentID,
            lessonIDStrs: lessonIDStrs,
            lessonMap: lessonMap,
            context: context
        )
        let presentations = fetchPresentations(
            studentIDStr: studentIDStr,
            lessonIDStrs: lessonIDStrs,
            lessonMap: lessonMap,
            context: context
        )
        let notes = fetchNotes(
            studentID: target.studentID,
            lessonIDStrs: lessonIDStrs,
            lessonMap: lessonMap,
            context: context
        )
        return StudentSequenceDetail(work: work, presentations: presentations, notes: notes)
    }

    // MARK: - Per-section helpers

    private static func fetchLessonMap(
        lessonIDs: [UUID],
        context: NSManagedObjectContext
    ) -> [UUID: CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id IN %@", lessonIDs)
        let lessons = context.safeFetch(request)
        // Sync can leave two rows with one id; keep the first rather than trap.
        return Dictionary(
            lessons.compactMap { lesson in
                guard let id = lesson.id else { return nil }
                return (id, lesson)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The work that counts as hers, by the rule her Children card files it by
    /// (`WorkVisibility`): the rows she owns, and a shared row she is on (project
    /// work) though another child owns it; never a classmate's linked copy naming
    /// her. Reading only the rows she owned, the card said Practicing while this
    /// sheet said "No work items" (bug hunt 2026-11-03 #26, finishing 10-29 #16).
    /// Every row of the lessons is read, open and closed: her closed copy is what
    /// tells a classmate's open copy apart from a row she shares.
    private static func fetchWork(
        studentID: UUID,
        lessonIDStrs: [String],
        lessonMap: [UUID: CDLesson],
        context: NSManagedObjectContext
    ) -> [WorkDetailItem] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID IN %@", lessonIDStrs)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkModel.assignedAt, ascending: false)]
        request.relationshipKeyPathsForPrefetching = ["participants"]
        let rows = context.safeFetch(request).filter { !$0.isDeleted }
        let visibility = WorkVisibility(rows: rows)
        return rows.filter { visibility.isVisible($0, to: studentID) }.map { work in
            let lessonUUID = UUID(uuidString: work.lessonID)
            let lessonName = lessonUUID.flatMap { lessonMap[$0]?.name } ?? "Lesson"
            return WorkDetailItem(
                id: work.id ?? UUID(),
                title: work.title.isEmpty ? lessonName : work.title,
                lessonName: lessonName,
                status: work.status,
                kind: work.kind,
                assignedAt: work.assignedAt
            )
        }
    }

    private static func fetchPresentations(
        studentIDStr: String,
        lessonIDStrs: [String],
        lessonMap: [UUID: CDLesson],
        context: NSManagedObjectContext
    ) -> [PresentationDetailItem] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        // Include undated "Previously Presented" records (stateRaw == presented,
        // presentedAt == nil) so the drill-in matches the dashboard grid.
        request.predicate = NSPredicate(
            format: "lessonID IN %@ AND (stateRaw == %@ OR presentedAt != nil)",
            lessonIDStrs, LessonAssignmentState.presented.rawValue
        )
        let assignments = context.safeFetch(request)
            .filter { $0.studentIDs.contains(studentIDStr) }
            .sorted { ($0.presentedAt ?? .distantPast) > ($1.presentedAt ?? .distantPast) }
        return assignments.map { la in
            let lessonUUID = UUID(uuidString: la.lessonID)
            let lessonName = lessonUUID.flatMap { lessonMap[$0]?.name }
                ?? la.lessonTitleSnapshot
                ?? "Lesson"
            return PresentationDetailItem(
                id: la.id ?? UUID(),
                lessonName: lessonName,
                presentedAt: la.presentedAt,
                notes: la.notes
            )
        }
    }

    /// The lessons' notes about her. Notes made from the presentation and work
    /// editors hang on the record they were written on (the presentation, the work
    /// or a check-in) and carry no `lessonID`, so every route back to the lesson is
    /// read, as the sequence recap reads them (`SequenceRecapDataLoader`); reading
    /// `lessonID` alone missed most of them (bug hunt 2026-11-03 #27).
    private static func fetchNotes(
        studentID: UUID,
        lessonIDStrs: [String],
        lessonMap: [UUID: CDLesson],
        context: NSManagedObjectContext
    ) -> [NoteDetailItem] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "lessonID IN %@", lessonIDStrs),
            NSPredicate(format: "lessonAssignment.lessonID IN %@", lessonIDStrs),
            NSPredicate(format: "work.lessonID IN %@", lessonIDStrs),
            NSPredicate(format: "workCheckIn.work.lessonID IN %@", lessonIDStrs)
        ])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)]
        request.relationshipKeyPathsForPrefetching = ["lessonAssignment", "work", "workCheckIn.work"]
        let scoped = context.safeFetch(request).filter { note in
            switch note.scope {
            case .all:                  return isOnRecord(of: note, studentID)
            case .student(let id):      return id == studentID
            case .students(let ids):    return ids.contains(studentID)
            }
        }
        return scoped.map { note in
            // The lesson the note reaches the sequence through: its own, or its record's.
            let lessonIDs = [
                note.lessonID, note.lessonAssignment?.lessonID, note.work?.lessonID, note.workCheckIn?.work?.lessonID
            ]
            let lessonName = lessonIDs.lazy
                .compactMap { $0.flatMap(UUID.init(uuidString:)).flatMap { lessonMap[$0]?.name } }
                .first ?? "Lesson"
            return NoteDetailItem(
                id: note.id ?? UUID(),
                lessonName: lessonName,
                body: note.body,
                createdAt: note.createdAt
            )
        }
    }

    /// A note for everyone is everyone's on a lesson, but on a presentation or a
    /// work it is about the children on that record: a classmate's presentation of
    /// the same lesson isn't hers.
    private static func isOnRecord(of note: CDNote, _ studentID: UUID) -> Bool {
        if let assignment = note.lessonAssignment {
            return assignment.studentIDs.contains(studentID.uuidString)
        }
        if let work = note.workCheckIn?.work ?? note.work {
            return WorkGrouping.involves(studentID, in: work)
        }
        return true
    }
}
