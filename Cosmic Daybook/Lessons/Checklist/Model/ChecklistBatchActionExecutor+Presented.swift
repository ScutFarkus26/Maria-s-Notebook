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

    // MARK: - Joining a presentation

    /// Puts the child on the presented row `attachment` describes, creating it when the
    /// context has none, and returns it. Then takes her off the other plans for the lesson
    /// that her year plan put her on, as recording a presentation does
    /// (`YearPlanReleaseService`): marked in the Checklist, she was still on Thursday's
    /// group (bug hunt 2026-11-03 #4). Shared by the cell's marks and the selection's.
    @discardableResult
    static func addStudentToPresentedLesson(
        student: CDStudent,
        lesson: CDLesson,
        in allLAs: [CDLessonAssignment],
        attachment: PresentedAttachment,
        context: NSManagedObjectContext
    ) -> CDLessonAssignment? {
        let studentIDString = student.cloudKitKey
        let today = Date()
        let given: CDLessonAssignment
        if let sequence = allLAs.first(where: { !$0.isDeleted && attachment.matches($0, today: today) }) {
            if !sequence.studentIDs.contains(studentIDString) {
                sequence.studentIDs.append(studentIDString)
            }
            given = sequence
        } else {
            guard let lessonID = lesson.id, let studentID = student.id else { return nil }
            given = attachment.makeAssignment(lessonID: lessonID, studentID: studentID, context: context)
        }
        // Only her: classmates already on a shared record keep their plans.
        YearPlanReleaseService.releaseRedundantPlans(after: given, only: [studentIDString], in: context)
        return given
    }

    // MARK: - History rows

    /// Files the mark on the child's latest history row for the lesson (`latestRow`), or
    /// makes one dated `givenOn`: the presentation's own date, nil for an undated one, so
    /// a mark with no presentation behind it never reads as given today (bug hunt
    /// 2026-11-03 #8).
    static func upsertLessonPresentation(
        studentID: String,
        lessonID: String,
        state: LessonPresentationState,
        from prefetchedLPs: [CDLessonPresentation],
        givenOn: Date? = Date(),
        context: NSManagedObjectContext
    ) {
        let rows = prefetchedLPs.filter { lp in
            !lp.isDeleted && lp.studentID == studentID && lp.lessonID == lessonID
        }
        if let existing = latestRow(of: rows) {
            if state == .proficient && existing.state != .proficient {
                existing.state = .proficient
                existing.masteredAt = Date()
            }
            existing.lastObservedAt = Date()
        } else {
            let lp = CDLessonPresentation(context: context)
            lp.studentID = studentID
            lp.lessonID = lessonID
            lp.state = state
            lp.presentedAt = givenOn
            lp.lastObservedAt = Date()
            lp.masteredAt = state == .proficient ? Date() : nil
        }
    }

    /// The row a mastery mark belongs on when a child holds several for one lesson (one
    /// per presentation, or old duplicates): the latest by date given, as the detail view
    /// and Claude's `mark_mastered` read it. The Checklist used to take whichever row the
    /// store returned first (bug hunt 2026-11-03 #15).
    static func latestRow(of rows: [CDLessonPresentation]) -> CDLessonPresentation? {
        rows.max { lhs, rhs in
            let left = (lhs.presentedAt ?? .distantPast, lhs.createdAt ?? .distantPast)
            let right = (rhs.presentedAt ?? .distantPast, rhs.createdAt ?? .distantPast)
            if left.0 != right.0 { return left.0 < right.0 }
            if left.1 != right.1 { return left.1 < right.1 }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }
}
