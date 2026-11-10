// ClassGridEngine+Brewing.swift
// Which of the Checklist's Inbox plans sit under Brewing in Lessons & Work, for
// the Brewing mark on their cells. The answer is the Inbox's own
// (`InboxPlacement`); this only shapes it for the matrix.

import Foundation
import CoreData

@MainActor
extension ClassGridEngine {

    /// The Inbox lessons that sit under Brewing in Lessons & Work, each with the children
    /// it is waiting on in roster order, by assignment id. The Inbox's own rule over the
    /// same record (`InboxPlacement`), judging the same children: `students`, the enrolled
    /// and shown roster. A lesson the Inbox shows under Ready isn't in the result.
    static func brewingPlans(
        inboxRows: [CDLessonAssignment],
        lessons: [CDLesson],
        students: [CDStudent],
        context: NSManagedObjectContext
    ) -> [UUID: [UUID]] {
        let roster = students.compactMap(\.id)
        let results = InboxPlacement.results(
            inboxRows: inboxRows, lessons: lessons, judgedStudentIDs: Set(roster), in: context
        )
        var held: [UUID: [UUID]] = [:]
        for (assignmentID, result) in results where result.isBlocked {
            let waitingOn = Set(result.perStudentReadiness.values.filter { !$0.isReady }.map(\.studentID))
            held[assignmentID] = roster.filter(waitingOn.contains)
        }
        return held
    }
}
