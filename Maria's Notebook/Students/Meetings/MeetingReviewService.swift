import Foundation
import CoreData
import OSLog

/// Service for creating and managing work reviews within meetings.
enum MeetingReviewService {
    private static let logger = Logger.students

    /// Creates a new work review record linking a meeting to a work item.
    @discardableResult
    static func createReview(
        meetingID: UUID,
        workID: UUID,
        noteText: String,
        context: NSManagedObjectContext
    ) -> CDMeetingWorkReview {
        let review = CDMeetingWorkReview(context: context)
        review.meetingIDUUID = meetingID
        review.workIDUUID = workID
        review.noteText = noteText
        review.createdAt = Date()

        // Wire up the relationship if the meeting exists
        let request = NSFetchRequest<CDStudentMeeting>(entityName: "StudentMeeting")
        request.predicate = NSPredicate(format: "id == %@", meetingID as CVarArg)
        request.fetchLimit = 1
        if let meeting = try? context.fetch(request).first {
            review.meeting = meeting
        }

        return review
    }

    /// Updates the note text on an existing review.
    static func updateReviewNote(_ review: CDMeetingWorkReview, noteText: String) {
        review.noteText = noteText
    }

    /// Fetches all work reviews for a given meeting.
    static func fetchReviews(
        meetingID: UUID,
        context: NSManagedObjectContext
    ) -> [CDMeetingWorkReview] {
        let request = NSFetchRequest<CDMeetingWorkReview>(entityName: "MeetingWorkReview")
        request.predicate = NSPredicate(format: "meetingID == %@", meetingID.uuidString)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Sets a work item to intentionally rest until a given date.
    static func setWorkResting(_ work: CDWorkModel, until date: Date) {
        work.restingUntil = AppCalendar.startOfDay(date)
        logger.debug("Work '\(work.title)' set to rest until \(date)")
    }

    /// Clears the resting state on a work item.
    static func clearWorkResting(_ work: CDWorkModel) {
        work.restingUntil = nil
        logger.debug("Work '\(work.title)' resting cleared")
    }

    /// Bulk-creates work review records from a dictionary of workID → noteText.
    /// Called when a meeting is completed to persist all reviews at once.
    static func persistReviews(
        meetingID: UUID,
        meeting: CDStudentMeeting,
        drafts: [UUID: String],
        reviewedIDs: Set<UUID>,
        context: NSManagedObjectContext
    ) {
        for workID in reviewedIDs {
            let review = CDMeetingWorkReview(context: context)
            review.meetingIDUUID = meetingID
            review.workIDUUID = workID
            review.noteText = drafts[workID] ?? ""
            review.meeting = meeting
            review.createdAt = Date()
        }
    }
}
