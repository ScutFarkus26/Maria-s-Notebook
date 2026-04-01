import Foundation
import CoreData
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

    static func safeFetch<T: NSManagedObject>(
        _ request: NSFetchRequest<T>, using context: NSManagedObjectContext,
        caller: String = #function
    ) -> [T] {
        do {
            return try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch \(T.self, privacy: .public): \(error.localizedDescription)")
            return []
        }
    }

    /// Cleans orphaned student IDs from a CDLessonAssignment by removing IDs that no longer exist in the database.
    /// This ensures referential integrity when using manual ID management instead of Core Data relationships.
    static func cleanOrphanedStudentIDs(
        for lessonAssignment: CDLessonAssignment,
        validStudentIDs: Set<String>,
        modelContext: NSManagedObjectContext
    ) {
        let originalIDs = lessonAssignment.studentIDs
        let cleanedIDs = originalIDs.filter { validStudentIDs.contains($0) }
        if cleanedIDs.count != originalIDs.count {
            lessonAssignment.studentIDs = cleanedIDs
        }
    }

    // MARK: - Fetch Helpers

    static func fetchWorkModel(presentationID: String, studentID: String, context: NSManagedObjectContext) throws -> CDWorkModel? {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID == %@ AND studentID == %@", presentationID, studentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchAllWorkModels(presentationID: String, context: NSManagedObjectContext) throws -> [CDWorkModel] {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID == %@", presentationID)
        return try context.fetch(request)
    }

    // MARK: - CDLessonPresentation Helpers

    /// Upsert CDLessonPresentation idempotently by (presentationID, studentID).
    /// If exists: updates lastObservedAt. If not exists: creates new with state .presented.
    static func upsertLessonPresentation(
        presentationID: String,
        studentID: String,
        lessonID: String,
        presentedAt: Date,
        context: NSManagedObjectContext
    ) throws {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "presentationID == %@ AND studentID == %@", presentationID, studentID)
        request.fetchLimit = 1
        let existing = try context.fetch(request).first

        if let existing {
            // Update lastObservedAt to track when this presentation was last seen
            existing.lastObservedAt = presentedAt
        } else {
            // Create new CDLessonPresentation with initial state .presented
            let lessonPresentation = CDLessonPresentation(context: context)
            lessonPresentation.studentID = studentID
            lessonPresentation.lessonID = lessonID
            lessonPresentation.presentationID = presentationID
            lessonPresentation.state = .presented
            lessonPresentation.presentedAt = presentedAt
            lessonPresentation.lastObservedAt = presentedAt
        }
    }

    /// Upsert CDLessonPresentation by (lessonID, studentID) when no presentationID exists.
    /// Used for syncing progress from CDLessonAssignment records that may not have a Presentation yet.
    static func upsertLessonPresentationByLessonAndStudent(
        lessonID: String,
        studentID: String,
        presentedAt: Date,
        context: NSManagedObjectContext
    ) throws {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "lessonID == %@ AND studentID == %@", lessonID, studentID)
        request.fetchLimit = 1
        let existing = try context.fetch(request).first

        if let existing {
            // Update lastObservedAt and presentedAt if the new date is earlier (preserve first presentation date)
            if let existingPresentedAt = existing.presentedAt, presentedAt < existingPresentedAt {
                existing.presentedAt = presentedAt
            }
            existing.lastObservedAt = presentedAt
        } else {
            // Create new CDLessonPresentation with initial state .presented (no presentationID yet)
            let lessonPresentation = CDLessonPresentation(context: context)
            lessonPresentation.studentID = studentID
            lessonPresentation.lessonID = lessonID
            lessonPresentation.presentationID = nil
            lessonPresentation.state = .presented
            lessonPresentation.presentedAt = presentedAt
            lessonPresentation.lastObservedAt = presentedAt
        }
    }
}
