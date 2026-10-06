import Foundation
import CoreData
import OSLog

struct LifecycleService {
    static let logger = Logger.lifecycle

    // MARK: - Fetch Helpers

    static func fetchWorkModel(
        presentationID: String,
        studentID: String,
        context: NSManagedObjectContext
    ) throws -> CDWorkModel? {
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
    /// If exists: moves presentedAt and lastObservedAt to `presentedAt`, since the
    /// row records this one presentation and a corrected date is its date.
    /// If not exists: creates new with state .presented.
    @discardableResult
    static func upsertLessonPresentation(
        presentationID: String,
        studentID: String,
        lessonID: String,
        presentedAt: Date,
        context: NSManagedObjectContext
    ) throws -> CDLessonPresentation {
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "presentationID == %@ AND studentID == %@", presentationID, studentID)
        request.fetchLimit = 1
        let existing = try context.fetch(request).first

        if let existing {
            if existing.presentedAt != presentedAt {
                existing.presentedAt = presentedAt
            }
            existing.lastObservedAt = presentedAt
            return existing
        } else {
            // Create new CDLessonPresentation with initial state .presented
            let lessonPresentation = CDLessonPresentation(context: context)
            lessonPresentation.studentID = studentID
            lessonPresentation.lessonID = lessonID
            lessonPresentation.presentationID = presentationID
            lessonPresentation.state = .presented
            lessonPresentation.presentedAt = presentedAt
            lessonPresentation.lastObservedAt = presentedAt
            return lessonPresentation
        }
    }
}
