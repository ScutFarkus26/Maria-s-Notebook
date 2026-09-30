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

import CoreData
import Foundation

enum PresentationRecordCleanup {

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

    // MARK: - Pieces

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
