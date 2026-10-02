//
//  PresentationRecordIndex+MasteryMarks.swift
//  Cosmic Daybook
//
//  Only the mastery marks, for a handful of lessons.
//
//  The checklist grid already reads its lessons' assignments and work itself,
//  so a full scoped index (presentations, assignments and year-plan entries)
//  would fetch the assignments a second time and the plan entries for nothing.
//  This is the index's "mastered" question on its own: one fetch of the marked
//  presentation rows for the lessons asked about, with the same definition
//  the fold uses (`masteredAt` set, or the proficient state).
//

import CoreData
import Foundation

nonisolated extension PresentationRecordIndex {

    /// lessonID → the children with a mastery mark on it, for `lessonIDs` only.
    /// Reads through `context`, unsaved edits included. Call on `context`'s queue.
    static func masteryMarks(
        lessonIDs: Set<String>,
        in context: NSManagedObjectContext
    ) -> [String: Set<String>] {
        guard !lessonIDs.isEmpty else { return [:] }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "lessonID IN %@ AND (masteredAt != nil OR stateRaw == %@)",
            Array(lessonIDs), LessonPresentationState.proficient.rawValue
        )
        var marks: [String: Set<String>] = [:]
        for row in context.safeFetch(request) where !row.isDeleted {
            marks[row.lessonID, default: []].insert(row.studentID)
        }
        return marks
    }
}
