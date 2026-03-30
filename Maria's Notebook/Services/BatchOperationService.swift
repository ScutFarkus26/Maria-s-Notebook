import Foundation
import SwiftData
import OSLog

/// Provides batch operations for notes, work items, and lesson assignments.
@MainActor
enum BatchOperationService {
    private static let logger = Logger.app(category: "BatchOperations")

    // MARK: - Batch Note Operations

    /// Add a tag to all notes within a date range.
    @discardableResult
    static func tagNotesByDateRange(
        start: Date,
        end: Date,
        tag: String,
        context: ModelContext
    ) -> Int {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> {
                $0.createdAt >= start && $0.createdAt <= end
            }
        )
        let notes = context.safeFetch(descriptor)
        var count = 0
        for note in notes {
            if !note.tags.contains(tag) {
                note.tags.append(tag)
                count += 1
            }
        }
        if count > 0 {
            context.safeSave()
            logger.info("Tagged \(count) notes with '\(tag)'")
        }
        return count
    }

    /// Add a tag to all notes for a specific student.
    @discardableResult
    static func tagNotesForStudent(
        studentID: UUID,
        tag: String,
        context: ModelContext
    ) -> Int {
        let notes = context.safeFetch(FetchDescriptor<Note>())
        let studentNotes = notes.filter {
            $0.searchIndexStudentID == studentID || $0.scopeIsAll
        }
        var count = 0
        for note in studentNotes {
            if !note.tags.contains(tag) {
                note.tags.append(tag)
                count += 1
            }
        }
        if count > 0 {
            context.safeSave()
            logger.info("Tagged \(count) notes for student \(studentID) with '\(tag)'")
        }
        return count
    }

    /// Bulk toggle includeInReport for a set of note IDs.
    @discardableResult
    static func markNotesForReport(
        noteIDs: Set<UUID>,
        include: Bool,
        context: ModelContext
    ) -> Int {
        let notes = context.safeFetch(FetchDescriptor<Note>())
        let matching = notes.filter { noteIDs.contains($0.id) }
        var count = 0
        for note in matching {
            if note.includeInReport != include {
                note.includeInReport = include
                count += 1
            }
        }
        if count > 0 {
            context.safeSave()
            logger.info("Marked \(count) notes includeInReport=\(include)")
        }
        return count
    }

    // MARK: - Batch Work Operations

    /// Create work items for multiple students from a lesson.
    @discardableResult
    static func assignWorkToStudents(
        title: String,
        studentIDs: [UUID],
        context: ModelContext
    ) -> Int {
        var count = 0
        for studentID in studentIDs {
            let work = WorkModel(
                title: title,
                studentID: studentID.uuidString
            )
            context.insert(work)
            count += 1
        }
        if count > 0 {
            context.safeSave()
            logger.info("Created \(count) work items for '\(title)'")
        }
        return count
    }

    // MARK: - Batch Lesson Assignment Operations

    /// Create draft lesson assignments for multiple student-lesson pairs.
    @discardableResult
    static func scheduleLessonsForStudents(
        lessonStudentPairs: [(lessonID: UUID, studentIDs: [UUID])],
        context: ModelContext
    ) -> Int {
        var count = 0
        for pair in lessonStudentPairs {
            let assignment = PresentationFactory.makeDraft(
                lessonID: pair.lessonID,
                studentIDs: pair.studentIDs
            )
            context.insert(assignment)
            count += 1
        }
        if count > 0 {
            context.safeSave()
            logger.info("Created \(count) lesson assignment drafts")
        }
        return count
    }
}
