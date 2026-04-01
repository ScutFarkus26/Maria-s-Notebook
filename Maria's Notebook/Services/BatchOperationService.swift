import Foundation
import CoreData
import OSLog

/// Provides batch operations for notes, work items, and lesson assignments.
@MainActor
enum BatchOperationService {
    private static let logger = Logger.app(category: "BatchOperations")

    // MARK: - Batch CDNote Operations

    /// Add a tag to all notes within a date range.
    @discardableResult
    static func tagNotesByDateRange(
        start: Date,
        end: Date,
        tag: String,
        context: NSManagedObjectContext
    ) -> Int {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "createdAt >= %@ AND createdAt <= %@",
            start as NSDate, end as NSDate
        )
        let notes = context.safeFetch(request)
        var count = 0
        for note in notes {
            if !note.tagsArray.contains(tag) {
                note.tagsArray.append(tag)
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
        context: NSManagedObjectContext
    ) -> Int {
        let notes = context.safeFetch(CDFetchRequest(CDNote.self))
        let studentNotes = notes.filter {
            $0.searchIndexStudentID == studentID || $0.scopeIsAll
        }
        var count = 0
        for note in studentNotes {
            if !note.tagsArray.contains(tag) {
                note.tagsArray.append(tag)
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
        context: NSManagedObjectContext
    ) -> Int {
        let notes = context.safeFetch(CDFetchRequest(CDNote.self))
        let matching = notes.filter { noteIDs.contains($0.id ?? UUID()) }
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
        context: NSManagedObjectContext
    ) -> Int {
        var count = 0
        for studentID in studentIDs {
            let work = CDWorkModel(context: context)
            work.title = title
            work.studentID = studentID.uuidString
            count += 1
        }
        if count > 0 {
            context.safeSave()
            logger.info("Created \(count) work items for '\(title)'")
        }
        return count
    }

    // MARK: - Batch CDLesson Assignment Operations

    /// Create draft lesson assignments for multiple student-lesson pairs.
    @discardableResult
    static func scheduleLessonsForStudents(
        lessonStudentPairs: [(lessonID: UUID, studentIDs: [UUID])],
        context: NSManagedObjectContext
    ) -> Int {
        var count = 0
        for pair in lessonStudentPairs {
            _ = PresentationFactory.makeDraft(
                lessonID: pair.lessonID,
                studentIDs: pair.studentIDs,
                context: context
            )
            count += 1
        }
        if count > 0 {
            context.safeSave()
            logger.info("Created \(count) lesson assignment drafts")
        }
        return count
    }
}
