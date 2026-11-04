//
//  YearPlanEntryRepair.swift
//  Cosmic Daybook
//
//  What a child's year plan puts right about its entries when it loads.
//
//  Three ways stored entries drift from the record (bug hunt 2026-11-03), each
//  put right in place:
//
//  - **Numbering (#24).** Add Sequence numbered an entry by its place in that
//    run's preview, so two runs (or a run over older entries) gave lessons one
//    and three both 0, and a drag cascaded onto the wrong lessons. An entry
//    takes its lesson's own `orderInSequence`. New entries are written that
//    way; this renumbers the ones written before, and follows a lesson the
//    guide reorders later.
//  - **A presentation that moved (#20).** A promoted entry takes its
//    presentation's day when the presentation moved somewhere the year plan
//    didn't hear of it (another screen, MCP, another device).
//  - **A lesson given without promotion (#21).** Quick record, Presented
//    Today and MCP's `record_presentation` don't promote. A planned entry
//    whose lesson she was given that way is promoted into the earliest such
//    presentation, on its day, so the plan draws the lesson once.
//
//  Each step writes only a value that differs from what is there, so a second
//  pass changes nothing. Every value is read from the lesson or the
//  presentation, so two devices repairing the same private-store entries
//  write the same values and agree once both have synced.
//

import CoreData
import Foundation

enum YearPlanEntryRepair {

    /// Puts one child's `entries` right against her presentations and their
    /// lessons. Returns how many entries changed. Does not save.
    ///
    /// - Parameters:
    ///   - lessonsByID: the entries' lessons, by id. An entry whose lesson
    ///     isn't here keeps its number.
    ///   - assignments: her presentations that are scheduled or given.
    @discardableResult
    static func repair(
        _ entries: [CDYearPlanEntry],
        lessonsByID: [String: CDLesson],
        assignments: [CDLessonAssignment]
    ) -> Int {
        let byID = Dictionary(
            assignments.compactMap { assignment in assignment.id.map { ($0.uuidString, assignment) } },
            uniquingKeysWith: { first, _ in first }
        )
        var unlinkedGiven = earliestUnlinkedGiven(
            in: assignments, linked: Set(entries.compactMap(\.promotedAssignmentID))
        )

        var changed = 0
        for entry in entries where !entry.isDeleted {
            var touched = false
            if let lesson = lessonsByID[entry.lessonID], entry.orderInSequence != lesson.orderInSequence {
                entry.orderInSequence = lesson.orderInSequence
                touched = true
            }
            let lessonKey = normalized(entry.lessonID)
            if entry.isPlanned, let given = unlinkedGiven[lessonKey],
               let id = given.id?.uuidString, let day = given.presentedAt {
                entry.status = .promoted
                entry.promotedAssignmentID = id
                entry.plannedDate = AppCalendar.startOfDay(day)
                unlinkedGiven[lessonKey] = nil
                touched = true
            } else if entry.isPromoted, let id = entry.promotedAssignmentID, let linked = byID[id],
                      let date = linked.scheduledFor ?? linked.presentedAt,
                      entry.plannedDate != AppCalendar.startOfDay(date) {
                entry.plannedDate = AppCalendar.startOfDay(date)
                touched = true
            }
            if touched {
                entry.modifiedAt = Date()
                changed += 1
            }
        }
        return changed
    }

    /// Her given presentations no entry links to, the earliest per lesson
    /// (by `normalized` lesson id): the one that answered the plan.
    private static func earliestUnlinkedGiven(
        in assignments: [CDLessonAssignment], linked: Set<String>
    ) -> [String: CDLessonAssignment] {
        var earliest: [String: CDLessonAssignment] = [:]
        for assignment in assignments where assignment.isGiven && !assignment.isDeleted {
            guard let id = assignment.id?.uuidString, !linked.contains(id),
                  let given = assignment.presentedAt, !assignment.lessonID.isEmpty else { continue }
            let lessonKey = normalized(assignment.lessonID)
            if let current = earliest[lessonKey]?.presentedAt, current <= given { continue }
            earliest[lessonKey] = assignment
        }
        return earliest
    }

    /// A lesson id as a UUID spells it, so an entry and a presentation that
    /// spell the same id in different case still meet.
    private static func normalized(_ id: String) -> String {
        UUID(uuidString: id)?.uuidString ?? id
    }
}
