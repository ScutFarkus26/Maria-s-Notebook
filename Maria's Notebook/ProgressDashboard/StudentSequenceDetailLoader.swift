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
    @MainActor
    static func load(
        target: StudentSequenceDetailTarget,
        context: NSManagedObjectContext
    ) -> StudentSequenceDetail {
        let studentIDStr = target.studentID.uuidString
        let lessonIDStrs = target.lessonIDs.map(\.uuidString)

        let lessonMap = fetchLessonMap(lessonIDs: target.lessonIDs, context: context)
        let work = fetchWork(
            studentIDStr: studentIDStr,
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
        let request = NSFetchRequest<CDLesson>(entityName: "Lesson")
        request.predicate = NSPredicate(format: "id IN %@", lessonIDs)
        let lessons = context.safeFetch(request)
        return Dictionary(uniqueKeysWithValues: lessons.compactMap { lesson in
            guard let id = lesson.id else { return nil }
            return (id, lesson)
        })
    }

    private static func fetchWork(
        studentIDStr: String,
        lessonIDStrs: [String],
        lessonMap: [UUID: CDLesson],
        context: NSManagedObjectContext
    ) -> [WorkDetailItem] {
        let request = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        request.predicate = NSPredicate(
            format: "studentID == %@ AND lessonID IN %@",
            studentIDStr,
            lessonIDStrs
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkModel.assignedAt, ascending: false)]
        let fetched = context.safeFetch(request)
        return fetched.map { work in
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
        let request = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
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

    private static func fetchNotes(
        studentID: UUID,
        lessonIDStrs: [String],
        lessonMap: [UUID: CDLesson],
        context: NSManagedObjectContext
    ) -> [NoteDetailItem] {
        let request = NSFetchRequest<CDNote>(entityName: "Note")
        request.predicate = NSPredicate(format: "lessonID IN %@", lessonIDStrs)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)]
        let scoped = context.safeFetch(request).filter { note in
            switch note.scope {
            case .all:                  return true
            case .student(let id):      return id == studentID
            case .students(let ids):    return ids.contains(studentID)
            }
        }
        return scoped.map { note in
            let lessonName: String
            if let lessonIDStr = note.lessonID, let lessonUUID = UUID(uuidString: lessonIDStr) {
                lessonName = lessonMap[lessonUUID]?.name ?? "Lesson"
            } else {
                lessonName = "Lesson"
            }
            return NoteDetailItem(
                id: note.id ?? UUID(),
                lessonName: lessonName,
                body: note.body,
                createdAt: note.createdAt
            )
        }
    }
}
