import Foundation
import SwiftData
import SwiftUI

extension StudentDetailViewModel {
    struct WorkSummary {
        let practiceLessonIDs: Set<UUID>
        let followUpLessonIDs: Set<UUID>
        let pendingPracticeLessonIDs: Set<UUID>
        let pendingFollowUpLessonIDs: Set<UUID>
        let pendingWorkLessonIDs: Set<UUID>
        static let empty = WorkSummary(
            practiceLessonIDs: [],
            followUpLessonIDs: [],
            pendingPracticeLessonIDs: [],
            pendingFollowUpLessonIDs: [],
            pendingWorkLessonIDs: []
        )
    }

    var workSummary: WorkSummary {
        let pending = contractSummary.pendingLessonIDs
        return WorkSummary(
            practiceLessonIDs: contractSummary.practiceLessonIDs,
            followUpLessonIDs: contractSummary.followUpLessonIDs,
            pendingPracticeLessonIDs: pending,
            pendingFollowUpLessonIDs: pending,
            pendingWorkLessonIDs: pending
        )
    }
}
