//
//  PresentationRecordIndex+OpenPlans.swift
//  Cosmic Daybook
//
//  The open plans on a lesson, with their dates.
//
//  `openPlanByLesson` answers "is she already planned for it?", which is all
//  the ready queue needs. The Groups page also says *when* and *with whom* ("on
//  Tue with Maya S and Ben K"), so the same fold keeps each unpresented
//  assignment whole, with its date, and each lesson's live year-plan entries
//  gathered by planned day. A promoted entry is left out, because the
//  presentation it became already speaks for it.
//

import CoreData
import Foundation

nonisolated extension PresentationRecordIndex {

    /// One plan to give a lesson that has not been given yet.
    struct OpenPlan: Sendable, Hashable {
        /// The unpresented `CDLessonAssignment`; nil for year-plan entries.
        let assignmentID: NSManagedObjectID?
        /// When it is planned: the assignment's `scheduledFor`, or the entries'
        /// planned day. Nil for an undated draft or an undated entry.
        let date: Date?
        /// The children on it, among those the index keeps.
        let studentIDs: [String]

        /// Year-plan entries rather than a presentation.
        var isYearPlan: Bool { assignmentID == nil }

        /// Soonest first, undated last; a presentation before year-plan
        /// entries on the same day; then by children and assignment, so the
        /// order is the same twice running and on either read path.
        static func precedes(_ lhs: OpenPlan, _ rhs: OpenPlan) -> Bool {
            switch (lhs.date, rhs.date) {
            case let (left?, right?) where left != right: return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            if lhs.isYearPlan != rhs.isYearPlan { return !lhs.isYearPlan }
            let leftChildren = lhs.studentIDs.joined(separator: ",")
            let rightChildren = rhs.studentIDs.joined(separator: ",")
            if leftChildren != rightChildren { return leftChildren < rightChildren }
            return (lhs.assignmentID?.uriRepresentation().absoluteString ?? "")
                < (rhs.assignmentID?.uriRepresentation().absoluteString ?? "")
        }
    }

    /// The lesson's open plans, soonest first.
    func openPlans(lesson lessonID: String) -> [OpenPlan] {
        openPlansByLesson[lessonID] ?? []
    }
}
