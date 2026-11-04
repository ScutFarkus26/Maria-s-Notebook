//
//  YearPlanNextLessons.swift
//  Cosmic Daybook
//
//  Where a child's year plan has her up to, read the Checklist's way.
//
//  The Checklist draws a year-plan entry as Planned only on the lesson she's up
//  to (`StudentChecklistRowState.isNextOnYearPlan`): the entry is still planned
//  (not promoted, not skipped) and the lesson before it in its sequence has
//  been given, or there is none. An entry further along waits on the lessons
//  before it. Until 2026-11-03 the Children view and the student's track
//  timeline read no year plan at all, so the lesson she was up to read Not
//  Started there and Planned on the Checklist, and the timeline offered Plan
//  Lesson on it, which scheduled it silently onto the entry's day (bug hunt
//  2026-11-03 #28). Both read this now.
//

import CoreData
import Foundation

enum YearPlanNextLessons {

    /// lessonID → the children (student id strings) whose year plan has them up
    /// to that lesson.
    /// - Parameters:
    ///   - sequences: each sequence's lesson ids in lesson order. The lesson
    ///     before an entry's is the one before it in its run; the first of a
    ///     run has none.
    ///   - students: the children to read; nil reads everyone.
    static func byLesson(
        sequences: [[String]], students: Set<String>?, in context: NSManagedObjectContext
    ) -> [String: Set<String>] {
        var precedingByLesson: [String: String] = [:]
        var lessonIDs: [String] = []
        for run in sequences {
            lessonIDs.append(contentsOf: run)
            for (before, lessonID) in zip(run, run.dropFirst()) where precedingByLesson[lessonID] == nil {
                precedingByLesson[lessonID] = before
            }
        }
        guard !lessonIDs.isEmpty, students?.isEmpty != true else { return [:] }

        let entries = plannedEntries(lessonIDs: lessonIDs, students: students, in: context)
        guard !entries.isEmpty else { return [:] }

        // Has she had the lesson before? The Checklist's answer: a presentation
        // record row or a presented assignment (`PresentationRecordIndex.given`).
        let precedingIDs = Set(entries.compactMap { precedingByLesson[$0.lessonID] })
        let index = precedingIDs.isEmpty ? nil : PresentationRecordIndex(
            lessonIDs: precedingIDs, students: Set(entries.map(\.studentID)), in: context
        )
        var result: [String: Set<String>] = [:]
        for entry in entries {
            if let before = precedingByLesson[entry.lessonID],
               index?.given(student: entry.studentID, lesson: before) == nil {
                continue
            }
            result[entry.lessonID, default: []].insert(entry.studentID)
        }
        return result
    }

    /// Entries still planned on `lessonIDs`: a promoted entry's presentation
    /// already speaks for it, and a skipped one is no plan (the Checklist's
    /// rule, `ClassGridEngine`'s year-plan read).
    private static func plannedEntries(
        lessonIDs: [String], students: Set<String>?, in context: NSManagedObjectContext
    ) -> [(lessonID: String, studentID: String)] {
        let request = CDFetchRequest(CDYearPlanEntry.self)
        var predicates = [NSPredicate(
            format: "lessonID IN %@ AND statusRaw == %@", lessonIDs, YearPlanEntryStatus.planned.rawValue
        )]
        if let students {
            predicates.append(NSPredicate(format: "studentID IN %@", Array(students)))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return context.safeFetch(request)
            .filter { !$0.isDeleted }
            .map { (lessonID: $0.lessonID, studentID: $0.studentID) }
    }
}
