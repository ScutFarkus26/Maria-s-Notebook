//
//  PresentationRecordCleanup.swift
//  Cosmic Daybook
//
//  What has to go with a presentation when it stops saying a child had it.
//
//  Two things hang off a presentation by id rather than by relationship, so
//  nothing removes them on its own. Its per-child history rows
//  (`CDLessonPresentation.presentationID`) are what the year plan and the
//  regive guard read as "given". Year-plan entries promoted into it
//  (`CDYearPlanEntry.promotedAssignmentID`) are what say "this plan answers
//  that intention". Deleting a presentation, un-marking it, or taking a child
//  off it left both behind: the child still read as given, and the entry
//  stayed promoted into a plan that no longer held her.
//
//  These helpers make the same writes Just Presented's Undo and
//  `discard_presentation` already made, for every other path. None of them
//  saves; the caller owns the save.
//
//  Folding one plan into another (a merge, a consolidation, a child dragged
//  between two plans, the draft dedup) is a fourth case: the plan that goes
//  away hands its notes and its promoted entries to the one that stays,
//  rather than cascading the notes away and stranding the entries.
//
//  Nonisolated: every helper only touches the context it is handed, so the
//  launch-time dedup (off the main actor) can use them as the views do.
//

import CoreData
import Foundation

nonisolated enum PresentationRecordCleanup {

    /// Call before `context.delete(assignment)`: its history rows go, and
    /// entries promoted into it go back to planned so the intention survives
    /// the plan.
    static func prepareToDelete(_ assignment: CDLessonAssignment, in context: NSManagedObjectContext) {
        guard let id = assignment.id?.uuidString else { return }
        deleteHistoryRows(presentationID: id, in: context)
        returnEntries(promotedInto: id, to: .planned, in: context)
    }

    /// The presentation is no longer marked given: its history rows go. It is
    /// still a plan, so entries promoted into it stay promoted.
    static func unmarkPresented(_ assignment: CDLessonAssignment, in context: NSManagedObjectContext) {
        guard let id = assignment.id?.uuidString else { return }
        deleteHistoryRows(presentationID: id, in: context)
    }

    /// Children taken off the presentation: their history rows for it go, and
    /// their entries promoted into it become `entryStatus` (planned, or skipped
    /// for a departure).
    static func removeStudents(
        _ studentIDs: Set<String>,
        from assignment: CDLessonAssignment,
        entriesBecome entryStatus: YearPlanEntryStatus = .planned,
        in context: NSManagedObjectContext
    ) {
        guard !studentIDs.isEmpty, let id = assignment.id?.uuidString else { return }
        deleteHistoryRows(presentationID: id, studentIDs: studentIDs, in: context)
        returnEntries(promotedInto: id, studentIDs: studentIDs, to: entryStatus, in: context)
    }

    /// Call before `context.delete(source)` when `source` is folded into
    /// `target` (two plans for the same lesson becoming one). The source's
    /// notes move to the target, since `unifiedNotes` cascades; an entry
    /// promoted into the source points at the target when the target now
    /// holds its child, and goes back to planned otherwise; the source's
    /// history rows go, as for any delete.
    static func prepareToMerge(
        _ source: CDLessonAssignment, into target: CDLessonAssignment, in context: NSManagedObjectContext
    ) {
        guard let sourceID = source.id?.uuidString, source.objectID != target.objectID else { return }
        moveNotes(from: source, to: target)
        let targetStudents = Set(target.studentIDs)
        for entry in entries(promotedInto: sourceID, in: context) {
            if targetStudents.contains(entry.studentID), let targetID = target.id?.uuidString {
                entry.promotedAssignmentID = targetID
            } else {
                entry.status = .planned
                entry.promotedAssignmentID = nil
            }
        }
        deleteHistoryRows(presentationID: sourceID, in: context)
    }

    /// Children moved from one plan to another (dragged between two groups,
    /// or moved to a new draft): their entries promoted into the source point
    /// at the target, which holds them now, notes about only them go with
    /// them, and their history rows on the source go. Rosters are the
    /// caller's to change.
    static func moveStudents(
        _ studentIDs: Set<String>,
        from source: CDLessonAssignment,
        to target: CDLessonAssignment,
        in context: NSManagedObjectContext
    ) {
        guard !studentIDs.isEmpty, let sourceID = source.id?.uuidString,
              let targetID = target.id?.uuidString, sourceID != targetID else { return }
        for entry in entries(promotedInto: sourceID, studentIDs: studentIDs, in: context) {
            entry.promotedAssignmentID = targetID
        }
        moveOwnNotes(of: studentIDs, from: source, to: target)
        deleteHistoryRows(presentationID: sourceID, studentIDs: studentIDs, in: context)
    }

    /// Re-parents the notes on `source` that are about only children in
    /// `studentIDs`. A note for the whole group, or one that also names a
    /// child who stays, stays (bug hunt 2026-10-16 #6).
    static func moveOwnNotes(
        of studentIDs: Set<String>, from source: CDLessonAssignment, to target: CDLessonAssignment
    ) {
        let notes = (source.unifiedNotes as? Set<CDNote>) ?? []
        for note in notes where !note.isDeleted {
            let about: [UUID]
            switch note.scope {
            case .all: continue
            case .student(let id): about = [id]
            case .students(let ids): about = ids
            }
            guard !about.isEmpty, about.allSatisfy({ studentIDs.contains($0.uuidString) }) else { continue }
            note.lessonAssignment = target
        }
    }

    /// The presentation's lesson was changed (Change Lesson, or a recording
    /// on another lesson): entries promoted into it for a different lesson go
    /// back to planned. It no longer answers them, and while they pointed at
    /// it the old lesson stayed promoted with nothing to give it and the year
    /// plan hid the presentation of the new one.
    static func returnEntriesForOtherLessons(
        promotedInto assignment: CDLessonAssignment, in context: NSManagedObjectContext
    ) {
        guard let id = assignment.id?.uuidString, !assignment.lessonID.isEmpty else { return }
        let lessonID = normalizedID(assignment.lessonID)
        for entry in entries(promotedInto: id, in: context) where normalizedID(entry.lessonID) != lessonID {
            entry.status = .planned
            entry.promotedAssignmentID = nil
        }
    }

    // MARK: - Pieces

    private static func normalizedID(_ id: String) -> String {
        UUID(uuidString: id)?.uuidString ?? id
    }

    /// Re-parents every note on `source` onto `target`.
    static func moveNotes(from source: CDLessonAssignment, to target: CDLessonAssignment) {
        let notes = (source.unifiedNotes as? Set<CDNote>) ?? []
        for note in notes where !note.isDeleted {
            note.lessonAssignment = target
        }
    }

    static func deleteHistoryRows(
        presentationID: String, studentIDs: Set<String>? = nil, in context: NSManagedObjectContext
    ) {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "presentationID == %@", presentationID)
        for row in context.safeFetch(request) where !row.isDeleted {
            if let studentIDs, !studentIDs.contains(row.studentID) { continue }
            context.delete(row)
        }
    }

    /// Entries still promoted into `planID`, optionally only these children's.
    static func entries(
        promotedInto planID: String, studentIDs: Set<String>? = nil, in context: NSManagedObjectContext
    ) -> [CDYearPlanEntry] {
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(format: "promotedAssignmentID == %@", planID)
        return context.safeFetch(request).filter { entry in
            entry.isPromoted && !entry.isDeleted
                && (studentIDs.map { $0.contains(entry.studentID) } ?? true)
        }
    }

    static func returnEntries(
        promotedInto planID: String,
        studentIDs: Set<String>? = nil,
        to status: YearPlanEntryStatus,
        in context: NSManagedObjectContext
    ) {
        for entry in entries(promotedInto: planID, studentIDs: studentIDs, in: context) {
            entry.status = status
            entry.promotedAssignmentID = nil
        }
    }
}
