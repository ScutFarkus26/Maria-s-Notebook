import Foundation
import SwiftData
import OSLog

/// Errors that can occur during lifecycle operations
enum LifecycleError: Error {
    case invalidLessonID(String)
    case invalidStudentID(String)
}

@MainActor
struct LifecycleService {
    static let logger = Logger.lifecycle

    // MARK: - Helper Methods

    static func safeFetch<T>(
        _ descriptor: FetchDescriptor<T>, using context: ModelContext,
        caller: String = #function
    ) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch \(T.self, privacy: .public): \(error.localizedDescription)")
            return []
        }
    }

    /// Cleans orphaned student IDs from a LessonAssignment by removing IDs that no longer exist in the database.
    /// This ensures referential integrity when using manual ID management instead of SwiftData relationships.
    static func cleanOrphanedStudentIDs(
        for lessonAssignment: LessonAssignment,
        validStudentIDs: Set<String>,
        modelContext: ModelContext
    ) {
        let originalIDs = lessonAssignment.studentIDs
        let cleanedIDs = originalIDs.filter { validStudentIDs.contains($0) }
        if cleanedIDs.count != originalIDs.count {
            lessonAssignment.studentIDs = cleanedIDs
            // Also update the transient relationship array
            lessonAssignment.students = lessonAssignment.students.filter { student in
                validStudentIDs.contains(student.cloudKitKey)
            }
        }
    }

    // MARK: - Fetch Helpers

    static func fetchWorkModel(presentationID: String, studentID: String, context: ModelContext) throws -> WorkModel? {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.presentationID == presentationID && work.studentID == studentID
            }
        )
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = 1
        return try context.fetch(limitedDescriptor).first
    }

    static func fetchAllWorkModels(presentationID: String, context: ModelContext) throws -> [WorkModel] {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.presentationID == presentationID
            }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - LessonPresentation Helpers

    /// Upsert LessonPresentation idempotently by (presentationID, studentID).
    /// If exists: updates lastObservedAt. If not exists: creates new with state .presented.
    static func upsertLessonPresentation(
        presentationID: String,
        studentID: String,
        lessonID: String,
        presentedAt: Date,
        context: ModelContext
    ) throws {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate { lp in
                lp.presentationID == presentationID && lp.studentID == studentID
            }
        )
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = 1
        let existing = try context.fetch(limitedDescriptor).first

        if let existing = existing {
            // Update lastObservedAt to track when this presentation was last seen
            existing.lastObservedAt = presentedAt
        } else {
            // Create new LessonPresentation with initial state .presented
            let lessonPresentation = LessonPresentation(
                studentID: studentID,
                lessonID: lessonID,
                presentationID: presentationID,
                state: .presented,
                presentedAt: presentedAt,
                lastObservedAt: presentedAt
            )
            context.insert(lessonPresentation)
        }
    }

    /// Upsert LessonPresentation by (lessonID, studentID) when no presentationID exists.
    /// Used for syncing progress from LessonAssignment records that may not have a Presentation yet.
    static func upsertLessonPresentationByLessonAndStudent(
        lessonID: String,
        studentID: String,
        presentedAt: Date,
        context: ModelContext
    ) throws {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate { lp in
                lp.lessonID == lessonID && lp.studentID == studentID
            }
        )
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = 1
        let existing = try context.fetch(limitedDescriptor).first

        if let existing = existing {
            // Update lastObservedAt and presentedAt if the new date is earlier (preserve first presentation date)
            if presentedAt < existing.presentedAt {
                existing.presentedAt = presentedAt
            }
            existing.lastObservedAt = presentedAt
        } else {
            // Create new LessonPresentation with initial state .presented (no presentationID yet)
            let lessonPresentation = LessonPresentation(
                studentID: studentID,
                lessonID: lessonID,
                presentationID: nil,
                state: .presented,
                presentedAt: presentedAt,
                lastObservedAt: presentedAt
            )
            context.insert(lessonPresentation)
        }
    }
}
