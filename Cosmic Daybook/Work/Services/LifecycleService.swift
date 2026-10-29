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
    /// If exists: moves presentedAt to `presentedAt`, since the row records this
    /// one presentation and a corrected date is its date, and moves it to
    /// `lessonID` when the presentation's lesson was changed. lastObservedAt
    /// follows a corrected date unless it is a later observation the new date
    /// doesn't pass; a save that keeps the date leaves it alone, since Recall
    /// and later observations move it on.
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
                let oldDate = existing.presentedAt
                existing.presentedAt = presentedAt
                if let observed = existing.lastObservedAt, observed != oldDate, observed > presentedAt {
                    // A later observation still stands.
                } else {
                    existing.lastObservedAt = presentedAt
                }
            }
            if !lessonID.isEmpty, existing.lessonID != lessonID {
                moveHistoryRow(existing, toLesson: lessonID)
            }
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

    /// Moves `assignment`'s per-child history rows (`presentationID` names it)
    /// to its current lesson. Change Lesson on a given presentation used to
    /// leave them on the old lesson, so the year plan, the regive guard and
    /// the Three-Year View kept reading the lesson she wasn't given. Rows
    /// already on the lesson are left alone. Doesn't save.
    @discardableResult
    static func relinkHistoryRows(of assignment: CDLessonAssignment, in context: NSManagedObjectContext) -> Int {
        guard let presentationID = assignment.id?.uuidString, !assignment.lessonID.isEmpty else { return 0 }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@ AND lessonID != %@", presentationID, assignment.lessonID
        )
        let stale = context.safeFetch(request).filter { !$0.isDeleted }
        for row in stale {
            moveHistoryRow(row, toLesson: assignment.lessonID)
        }
        return stale.count
    }

    /// One history row onto another lesson. Its track and step named the old
    /// lesson's place, so they are cleared; `TrackProgressResolver` then
    /// places the row by its lesson, as it does every row recording makes.
    private static func moveHistoryRow(_ row: CDLessonPresentation, toLesson lessonID: String) {
        row.lessonID = lessonID
        row.trackID = nil
        row.trackStepID = nil
    }
}
