import CoreData
import Foundation

@MainActor
enum PresentationFollowUpService {
    static func beginFollowing(_ row: CDLessonPresentation, at date: Date) {
        guard row.followUpActionRaw == nil, row.followUpResolvedAt == nil else { return }
        row.followUpAction = .watchWork
        row.followUpReviewAt = nil
        row.followUpResolutionRaw = nil
        row.followUpEvidenceRaw = nil
        row.followUpNote = nil
        row.followUpSupportRaw = nil
        row.followUpUpdatedAt = date
    }

    static func setAction(
        _ action: PresentationFollowUpAction,
        for rows: [CDLessonPresentation],
        reviewAt: Date? = nil,
        support: PresentationFollowUpSupport? = nil,
        calendar: Calendar = AppCalendar.shared,
        now: Date = Date()
    ) {
        for row in rows where row.hasOpenFollowUp {
            row.followUpAction = action
            row.followUpReviewAt = action == .checkWork
                ? reviewAt.map(calendar.startOfDay(for:))
                : nil
            row.followUpSupport = action == .planSupport ? (support ?? .represent) : nil
            row.followUpUpdatedAt = now
        }
    }

    static func saveObservation(
        evidence: Set<PresentationFollowUpEvidence>,
        note: String,
        for row: CDLessonPresentation,
        now: Date = Date()
    ) {
        row.followUpEvidence = evidence
        let trimmed = note.trimmed()
        row.followUpNote = trimmed.isEmpty ? nil : trimmed
        row.lastObservedAt = now
        row.followUpUpdatedAt = now
    }

    static func resolve(
        _ resolution: PresentationFollowUpResolution,
        row: CDLessonPresentation,
        at date: Date = Date()
    ) {
        guard row.followUpActionRaw != nil else { return }
        row.followUpResolution = resolution
        row.followUpResolvedAt = date
        row.followUpUpdatedAt = date
        row.lastObservedAt = date
    }

    static func reopen(_ row: CDLessonPresentation, at date: Date = Date()) {
        guard row.followUpActionRaw != nil else { return }
        row.followUpResolvedAt = nil
        row.followUpResolutionRaw = nil
        row.followUpUpdatedAt = date
    }

    static func rows(
        for presentationID: UUID,
        in context: NSManagedObjectContext
    ) -> [CDLessonPresentation] {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@",
            presentationID.uuidString
        )
        request.sortDescriptors = [NSSortDescriptor(key: "studentID", ascending: true)]
        return context.safeFetch(request)
    }

    static func hasOpenFollowUps(
        for presentationID: UUID?,
        in context: NSManagedObjectContext
    ) -> Bool {
        guard let presentationID else { return false }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "presentationID == %@ AND followUpActionRaw != nil AND followUpResolvedAt == nil",
            presentationID.uuidString
        )
        return !context.safeFetch(request).isEmpty
    }
}
