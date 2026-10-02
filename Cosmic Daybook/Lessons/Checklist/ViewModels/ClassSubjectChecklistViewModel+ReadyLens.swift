// ClassAreaChecklistViewModel+ReadyLens.swift
// The Ready to Present lens: how many cells on screen are Ready (the toolbar's count),
// how many in one row (the Class column's "5 ready"), and the row's Plan, a draft for
// exactly those children made the way the card's Present makes one (+Presenting).
// Ready is the cell's Ready mark: not presented, not planned, nothing holding it back.

import Foundation
import CoreData

extension ClassAreaChecklistViewModel {

    var isReadyLens: Bool { lens == .ready }

    /// Ready cells over the rows and children on screen: the toolbar's "(12)".
    var readyTotal: Int { statusCounts[.ready] }

    /// Ready children on screen for one lesson: the Class column's "5 ready".
    func readyCount(for lessonID: UUID?) -> Int {
        guard let lessonID else { return 0 }
        return rowSummaries[lessonID]?.ready ?? 0
    }

    /// The row's Plan: a saved draft of `lessonID` for every child on screen who is
    /// Ready for it, in column order, for the present-a-lesson sheet to record or
    /// schedule. Nil when no one is ready.
    func makeReadyDraft(
        lessonID: UUID, studentOrder: [UUID], context: NSManagedObjectContext
    ) -> CDLessonAssignment? {
        let ready = readyStudentIDs(for: lessonID, studentOrder: studentOrder)
        guard !ready.isEmpty else { return nil }
        return makePresentationDraft(lessonID: lessonID, studentIDs: ready, context: context)
    }
}
