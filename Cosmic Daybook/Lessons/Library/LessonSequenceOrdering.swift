//
//  LessonSequenceOrdering.swift
//  Cosmic Daybook
//
//  Moving a lesson within its sequence: drag onto another lesson, or Move
//  Earlier / Move Later. Always over the whole sequence, named by lesson id,
//  then renumbered 0, 1, 2… so `orderInSequence` has no ties.
//
//  The drag used to send list positions from the thread view (every lesson)
//  that the Lessons screen applied to its own list (only what the filter chips
//  let through), so with a chip on the wrong lesson moved and only the visible
//  ones were renumbered (bug hunt 2026-10-10, #43). Move Earlier/Later swapped
//  two values, so two lessons sharing a number (a new lesson used to take 0)
//  didn't move at all (#44).
//

import CoreData
import Foundation

enum LessonSequenceOrdering {

    /// A sequence's lessons in the order the map shows them.
    static func sorted(_ lessons: [CDLesson]) -> [CDLesson] {
        lessons.sorted(by: ThreadRowData.lessonSortOrder)
    }

    /// Drops `movedID` onto `targetID`: moving later lands just after the
    /// target, moving earlier just before it (SwiftUI's `onMove` convention).
    /// Renumbers the whole sequence. False when either lesson isn't in it.
    @discardableResult
    static func move(_ movedID: UUID, onto targetID: UUID, in sequenceLessons: [CDLesson]) -> Bool {
        var ordered = sorted(sequenceLessons)
        guard movedID != targetID,
              let source = ordered.firstIndex(where: { $0.id == movedID }),
              let target = ordered.firstIndex(where: { $0.id == targetID }) else { return false }
        // Once the moved lesson is out of the list, the target's old index is where it
        // lands either way: just after the target going later, just before it going earlier.
        let moved = ordered.remove(at: source)
        ordered.insert(moved, at: target)
        renumber(ordered)
        return true
    }

    /// Move Earlier (`offset` -1) or Move Later (+1) by one place. Renumbers
    /// the whole sequence, so a tie can't swallow the move. False at either end.
    @discardableResult
    static func step(_ lessonID: UUID, by offset: Int, in sequenceLessons: [CDLesson]) -> Bool {
        var ordered = sorted(sequenceLessons)
        guard let index = ordered.firstIndex(where: { $0.id == lessonID }) else { return false }
        let destination = index + offset
        guard destination >= 0, destination < ordered.count, destination != index else { return false }
        ordered.swapAt(index, destination)
        renumber(ordered)
        return true
    }

    /// Writes 0, 1, 2… as `orderInSequence`, touching only lessons whose number changes.
    static func renumber(_ ordered: [CDLesson]) {
        for (index, lesson) in ordered.enumerated() where lesson.orderInSequence != Int64(index) {
            lesson.orderInSequence = Int64(index)
        }
    }
}
