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

    /// The children among `studentIDs` with a mastery mark on `lessonID`, each with the
    /// day it was first marked (nil when a mark has no date: the proficient state alone).
    /// Several rows can carry a mark for one child (a lesson given again adds a row);
    /// any marked row counts, as in `masteryMarks`. Call on `context`'s queue.
    static func masteryDates(
        lessonID: String,
        studentIDs: [String],
        in context: NSManagedObjectContext
    ) -> [String: Date?] {
        guard !lessonID.isEmpty, !studentIDs.isEmpty else { return [:] }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "lessonID == %@ AND studentID IN %@ AND (masteredAt != nil OR stateRaw == %@)",
            lessonID, studentIDs, LessonPresentationState.proficient.rawValue
        )
        var dates: [String: Date?] = [:]
        for row in context.safeFetch(request) where !row.isDeleted {
            let earlier: Date? = switch (dates[row.studentID] ?? nil, row.masteredAt) {
            case let (old?, new?): min(old, new)
            case let (old, new): old ?? new
            }
            dates[row.studentID] = earlier
        }
        return dates
    }
}
