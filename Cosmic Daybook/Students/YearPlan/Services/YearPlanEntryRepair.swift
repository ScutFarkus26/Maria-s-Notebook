//
//  YearPlanEntryRepair.swift
//  Cosmic Daybook
//
//  What a child's year plan puts right about its entries when it loads, and
//  what every launch puts right for the whole notebook.
//
//  Four ways stored entries drift from the record, each put right in place
//  (the first three from bug hunt 2026-11-03):
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
//  - **A presentation that is gone (domain-logic review R17).** An entry
//    promoted into a presentation no longer in the store (deleted on another
//    device, or by a path that skipped `PresentationRecordCleanup`) goes back
//    to planned, as an in-app delete sends it. An undated draft in the Inbox
//    still counts as there. An entry changed within the last day is left for
//    later: its presentation may simply not have synced in yet. One sent
//    back too soon (its scheduled presentation arrived later) is promoted
//    into it again: a planned entry whose lesson is scheduled for her, on a
//    presentation no entry links to, is promoted into the earliest such one,
//    as scheduling it in the app would have done (Phase 10 review, finding 4).
//
//  Each step writes only a value that differs from what is there, so a second
//  pass changes nothing. Every value is read from the lesson or the
//  presentation, so two devices repairing the same private-store entries
//  write the same values and agree once both have synced.
//

import CoreData
import Foundation

nonisolated enum YearPlanEntryRepair {

    /// Puts one child's `entries` right against her presentations and their
    /// lessons. Returns how many entries changed. Does not save.
    ///
    /// - Parameters:
    ///   - lessonsByID: the entries' lessons, by id. An entry whose lesson
    ///     isn't here keeps its number.
    ///   - assignments: her presentations that are scheduled or given.
    ///   - existingAssignmentIDs: which of the presentations the entries are
    ///     promoted into are in the store, dated or not
    ///     (`existingAssignmentIDs(linkedFrom:in:)`). Nil skips that step.
    @discardableResult
    static func repair(
        _ entries: [CDYearPlanEntry],
        lessonsByID: [String: CDLesson],
        assignments: [CDLessonAssignment],
        existingAssignmentIDs: Set<String>? = nil,
        now: Date = Date()
    ) -> Int {
        let byID = Dictionary(
            assignments.compactMap { assignment in assignment.id.map { ($0.uuidString, assignment) } },
            uniquingKeysWith: { first, _ in first }
        )
        let linked = Set(entries.compactMap(\.promotedAssignmentID))
        var unlinkedGiven = earliestUnlinkedGiven(in: assignments, linked: linked)
        var unlinkedScheduled = earliestUnlinkedScheduled(in: assignments, linked: linked)

        var changed = 0
        for entry in entries where !entry.isDeleted {
            var touched = false
            if let lesson = lessonsByID[entry.lessonID], entry.orderInSequence != lesson.orderInSequence {
                entry.orderInSequence = lesson.orderInSequence
                touched = true
            }
            if let existing = existingAssignmentIDs, entry.isPromoted,
               let id = entry.promotedAssignmentID, !existing.contains(normalized(id)),
               (entry.modifiedAt ?? .distantPast) < now.addingTimeInterval(-orphanGrace) {
                // As `PresentationRecordCleanup.returnEntries(promotedInto:to:)` sends it.
                entry.status = .planned
                entry.promotedAssignmentID = nil
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
            } else if entry.isPlanned, let scheduled = unlinkedScheduled[lessonKey],
                      let id = scheduled.id?.uuidString, let day = scheduled.scheduledFor {
                entry.status = .promoted
                entry.promotedAssignmentID = id
                entry.plannedDate = AppCalendar.startOfDay(day)
                unlinkedScheduled[lessonKey] = nil
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

    /// How long an entry promoted into a missing presentation is left alone
    /// after it last changed: a day, so a presentation still on its way from
    /// another device isn't mistaken for one deleted.
    static let orphanGrace: TimeInterval = 24 * 60 * 60

    /// The ids of the presentations `entries` are promoted into that are in
    /// the store, scheduled, given or an undated draft alike, spelled as
    /// `normalized` spells them. One fetch.
    static func existingAssignmentIDs(
        linkedFrom entries: [CDYearPlanEntry], in context: NSManagedObjectContext
    ) -> Set<String> {
        let linked = entries.filter(\.isPromoted).compactMap { $0.promotedAssignmentID.flatMap(UUID.init(uuidString:)) }
        guard !linked.isEmpty else { return [] }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id IN %@", linked)
        return Set(context.safeFetch(request).filter { !$0.isDeleted }.compactMap { $0.id?.uuidString })
    }

    // MARK: - The Whole Notebook

    /// `repair` for every child's entries at once: what each launch runs, so
    /// the plan is put right wherever it is read (the Checklist, Groups,
    /// Claude's tools), not only on the year-plan screen.
    /// A few fetches for the whole store. Does not save.
    @discardableResult
    static func repairAll(in context: NSManagedObjectContext) -> Int {
        let entries = context.safeFetch(CDFetchRequest(CDYearPlanEntry.self)).filter { !$0.isDeleted }
        guard !entries.isEmpty else { return 0 }
        var lessonsByID: [String: CDLesson] = [:]
        let lessonIDs = Set(entries.map(\.lessonID)).compactMap(UUID.init(uuidString:))
        let lessonRequest = CDFetchRequest(CDLesson.self)
        lessonRequest.predicate = NSPredicate(format: "id IN %@", lessonIDs)
        for lesson in context.safeFetch(lessonRequest) {
            guard let id = lesson.id else { continue }
            // Keyed both ways an entry may spell its lesson id.
            lessonsByID[id.uuidString] = lesson
            lessonsByID[id.uuidString.lowercased()] = lesson
        }
        let assignmentRequest = CDFetchRequest(CDLessonAssignment.self)
        assignmentRequest.predicate = NSPredicate(format: "scheduledFor != nil OR presentedAt != nil")
        var assignmentsByStudent: [String: [CDLessonAssignment]] = [:]
        for assignment in context.safeFetch(assignmentRequest) where !assignment.isDeleted {
            for studentID in Set(assignment.studentIDs) {
                assignmentsByStudent[studentID, default: []].append(assignment)
            }
        }
        let existing = existingAssignmentIDs(linkedFrom: entries, in: context)
        return Dictionary(grouping: entries, by: \.studentID).reduce(0) { total, group in
            total + repair(
                group.value, lessonsByID: lessonsByID,
                assignments: assignmentsByStudent[group.key] ?? [],
                existingAssignmentIDs: existing
            )
        }
    }

    /// The launch step: lessons tied in their sub-area are renumbered first
    /// (`LessonOrder.renumberTies`), since entries copy their lesson's number,
    /// then `repairAll`; saved when either changed anything.
    @discardableResult
    static func repairAllAndSave(in context: NSManagedObjectContext) -> Int {
        let renumbered = LessonOrder.renumberTies(in: context.safeFetch(CDFetchRequest(CDLesson.self)))
        let changed = repairAll(in: context)
        if renumbered + changed > 0 { context.safeSave() }
        return changed
    }

    // MARK: - Helpers

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

    /// Her scheduled presentations not yet given that no entry links to, the
    /// earliest per lesson (by day, then id, so two devices pick the same).
    private static func earliestUnlinkedScheduled(
        in assignments: [CDLessonAssignment], linked: Set<String>
    ) -> [String: CDLessonAssignment] {
        var earliest: [String: CDLessonAssignment] = [:]
        for assignment in assignments where !assignment.isGiven && !assignment.isDeleted {
            guard let id = assignment.id?.uuidString, !linked.contains(id),
                  let day = assignment.scheduledFor, !assignment.lessonID.isEmpty else { continue }
            let lessonKey = normalized(assignment.lessonID)
            if let current = earliest[lessonKey], let currentDay = current.scheduledFor,
               currentDay < day || (currentDay == day && (current.id?.uuidString ?? "") < id) { continue }
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
