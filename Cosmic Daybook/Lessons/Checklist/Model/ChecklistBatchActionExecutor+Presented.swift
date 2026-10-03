import CoreData
import Foundation

// MARK: - Presented Helpers

extension ChecklistBatchActionExecutor {

    /// Which "presented" row a mark joins when the child is not on one already.
    ///
    /// This is the only thing that separates *Mark Presented* from *Mark
    /// Previously Presented*: the first means "today", and attaches to today's
    /// presentation; the second means "before this notebook existed", and
    /// attaches to the undated row that deliberately carries no date at all.
    /// Everything either mark does afterwards — the roster edit, the track
    /// enrolment, the `CDLessonPresentation` upsert — is identical, so they run
    /// the same code with this passed in.
    enum PresentedAttachment {
        case today
        case undated

        /// The row this mark should join, when the context already holds one.
        func matches(_ assignment: CDLessonAssignment, today: Date) -> Bool {
            guard assignment.isPresented else { return false }
            switch self {
            case .today:
                return (assignment.presentedAt ?? Date.distantPast).isSameDay(as: today)
            case .undated:
                return assignment.presentedAt == nil
            }
        }

        /// The row this mark creates when there is nothing to join.
        func makeAssignment(
            lessonID: UUID,
            studentID: UUID,
            context: NSManagedObjectContext
        ) -> CDLessonAssignment {
            switch self {
            case .today:
                PresentationFactory.makePresented(
                    lessonID: lessonID, studentIDs: [studentID], context: context
                )
            case .undated:
                PresentationFactory.makePreviouslyPresented(
                    lessonID: lessonID, studentIDs: [studentID], context: context
                )
            }
        }
    }

    static func deleteLessonPresentation(
        studentID: String, lessonID: String,
        from prefetchedLPs: [CDLessonPresentation],
        context: NSManagedObjectContext
    ) {
        // Filter from pre-fetched data instead of re-fetching all LessonPresentations
        let toDelete = prefetchedLPs.filter { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }
        for lp in toDelete {
            context.delete(lp)
        }
    }
}
