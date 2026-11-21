//
//  LessonRepository+AreaOrder.swift
//  Cosmic Daybook
//
//  An area's sub-areas in the map's order, a sub-area's lessons in taught
//  order, and the area-wide `sortIndex` rebuilt from both.
//
//  `orderInSequence` is the truth within a sub-area; `sortIndex` is derived,
//  an area-wide index the area view and the lesson pickers sort on, rebuilt
//  by walking the area's sub-areas in the map's saved order and numbering
//  every lesson. Claude's curriculum tools and the lesson editor both settle
//  an edit through here, so a tool edit and a Save on the lesson card leave
//  the same numbers. The editor used to move a lesson to another sub-area
//  without rebuilding it (domain-logic review A15).
//

import CoreData
import Foundation

extension LessonRepository {

    /// The label lessons filed without a sub-area are read under.
    static let ungroupedSequenceLabel = SubAreaOrder.ungroupedName

    /// The area's sub-areas in the map's saved order, with "Ungrouped" where
    /// the guide placed it when any lesson is filed without one — the same
    /// list `LessonsRootView.syncReorderableSequences` builds. Appending it
    /// last instead moved unfiled lessons to the end of the area's
    /// `sortIndex` on every tool edit (bug hunt 2026-10-12, #28).
    static func orderedSequences(inArea area: String, from lessons: [CDLesson]) -> [String] {
        let sequences = LessonsViewModel().groups(for: area, lessons: lessons)
        let hasUngrouped = lessons.contains { sameFiling($0.area, area) && $0.sequence.trimmed().isEmpty }
        guard hasUngrouped else { return sequences }
        return FilterOrderStore.loadSequenceOrder(
            for: area.trimmed(), existing: sequences + [ungroupedSequenceLabel]
        )
        // A sub-area once typed as "ungrouped" folds into the label; spell it one way.
        .map { isUngroupedLabel($0) ? ungroupedSequenceLabel : $0 }
    }

    /// The lessons filed under one sub-area in the one lesson order
    /// (`LessonOrder`). Pass `ungroupedSequenceLabel` for lessons filed with
    /// no sub-area; it also takes in any sub-area literally named
    /// "Ungrouped", which `orderedSequences` folds into the label.
    static func lessonsInSequence(
        _ sequence: String, area: String, from lessons: [CDLesson]
    ) -> [CDLesson] {
        LessonOrder.sorted(lessons.filter { lesson in
            guard sameFiling(lesson.area, area) else { return false }
            if isUngroupedLabel(sequence) {
                return lesson.sequence.trimmed().isEmpty || isUngroupedLabel(lesson.sequence)
            }
            return sameFiling(lesson.sequence, sequence)
        })
    }

    /// Walks the area's sub-areas in the map's order and numbers every lesson,
    /// so the area view and the pickers that sort on `sortIndex` agree with
    /// the sub-areas. Writes only the numbers that change. Does not save.
    static func rebuildSortIndex(forArea area: String, from lessons: [CDLesson]) {
        var position: Int64 = 0
        for sequence in orderedSequences(inArea: area, from: lessons) {
            for lesson in lessonsInSequence(sequence, area: area, from: lessons) {
                if lesson.sortIndex != position { lesson.sortIndex = position }
                position += 1
            }
        }
    }

    /// `rebuildSortIndex(forArea:from:)` over every lesson in the store.
    func rebuildSortIndex(forArea area: String) {
        Self.rebuildSortIndex(forArea: area, from: context.safeFetch(CDFetchRequest(CDLesson.self)))
    }

    /// Area and sub-area names compare the way the Lessons screens compare
    /// them: trimmed and case-insensitive.
    static func sameFiling(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmed().caseInsensitiveCompare(rhs.trimmed()) == .orderedSame
    }

    static func isUngroupedLabel(_ name: String) -> Bool {
        sameFiling(name, ungroupedSequenceLabel)
    }
}
