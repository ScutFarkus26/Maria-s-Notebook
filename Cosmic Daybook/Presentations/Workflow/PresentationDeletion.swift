//
//  PresentationDeletion.swift
//  Cosmic Daybook
//
//  Deleting a presentation from the history, and taking a child off a plan in
//  Merge Groups (bug hunt 2026-11-03 #1, #3). Both used to run at once: the
//  history's Delete took every history row of the presentation, mastery marks
//  included, and its notes cascaded with it; Remove deleted a plan emptied of
//  its last child, notes and all.
//
//  Now each asks first when there is something to lose (a given presentation,
//  notes, a mastery mark), naming what goes and what stays, as the checklist
//  cell's Clear does. What the teacher wrote stays with the children: notes on
//  the presentation come off it (they would cascade) and become theirs, a note
//  for the whole group naming every child on it, filed under the lesson; the
//  text of a history row that goes is kept as a note on its child. Mastery
//  marks stand on their own (`ChecklistRosterRemoval.keepMasteryMarks`).
//
//  A plan with no notes and no marks still goes without a question. Nothing
//  here saves; the caller owns the save. On the main actor, as
//  `ChecklistRosterRemoval` is.
//

import CoreData
import Foundation

enum PresentationDeletion {

    /// What a delete would take with it, for the question asked first.
    struct Summary: Equatable, Sendable {
        var isGiven = false
        /// Notes written on the presentation; they stay, on the children.
        var notes = 0
        /// Children with a mastery mark filed on it; the marks stay.
        var masteryMarks = 0

        /// A given presentation leaves the children's history, so it always asks.
        var needsConfirmation: Bool { isGiven || notes > 0 || masteryMarks > 0 }
    }

    /// A delete waiting for the guide's yes.
    struct Request: Identifiable {
        let assignment: CDLessonAssignment
        let summary: Summary
        let title: String
        let message: String
        let confirmTitle: String
        /// For Merge Groups' Remove: the child taken off; nil for a delete.
        let studentID: String?

        var id: NSManagedObjectID { assignment.objectID }
    }

    // MARK: - Asking first

    /// Counts what `assignment` carries. Touches nothing.
    static func summary(of assignment: CDLessonAssignment, in context: NSManagedObjectContext) -> Summary {
        let notes = ((assignment.unifiedNotes as? Set<CDNote>) ?? []).filter { !$0.isDeleted }.count
        var marked = Set<String>()
        if let id = assignment.id?.uuidString {
            let request = CDFetchRequest(CDLessonPresentation.self)
            request.predicate = NSPredicate(
                format: "presentationID == %@ AND (masteredAt != nil OR stateRaw == %@)",
                id, LessonPresentationState.proficient.rawValue
            )
            marked = Set(context.safeFetch(request).filter { !$0.isDeleted }.map(\.studentID))
        }
        return Summary(isGiven: assignment.isPresented, notes: notes, masteryMarks: marked.count)
    }

    /// The history's Delete: nil when there is nothing to lose (go ahead),
    /// otherwise the question. `childNames` are the children on it, short names.
    static func deleteRequest(
        for assignment: CDLessonAssignment, childNames: [String], in context: NSManagedObjectContext
    ) -> Request? {
        let summary = summary(of: assignment, in: context)
        guard summary.needsConfirmation else { return nil }
        let who = children(childNames)
        var lines: [String] = []
        if summary.isGiven { lines.append("It will no longer show as given to \(who).") }
        if let notes = notesLine(summary.notes, who: who) { lines.append(notes) }
        if summary.masteryMarks > 0 { lines.append("Mastery marks stay.") }
        return Request(
            assignment: assignment,
            summary: summary,
            title: "Delete This Presentation?",
            message: lines.joined(separator: " "),
            confirmTitle: "Delete",
            studentID: nil
        )
    }

    /// Merge Groups' Remove: nil unless taking her off empties a plan with
    /// notes or marks on it. Taking one child of several off asks nothing:
    /// the plan stays, with its notes, and her marks stay.
    static func removeRequest(
        _ studentID: String, childName: String, from assignment: CDLessonAssignment,
        in context: NSManagedObjectContext
    ) -> Request? {
        guard emptiedByRemoving(studentID, from: assignment) else { return nil }
        let summary = summary(of: assignment, in: context)
        guard summary.needsConfirmation else { return nil }
        let trimmed = childName.trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? "this child" : trimmed
        var lines = ["No one else is on this plan, so it will be deleted."]
        if let notes = notesLine(summary.notes, who: name) { lines.append(notes) }
        if summary.masteryMarks > 0 { lines.append("Mastery marks stay.") }
        return Request(
            assignment: assignment,
            summary: summary,
            title: "Remove \(name)?",
            message: lines.joined(separator: " "),
            confirmTitle: "Remove",
            studentID: studentID
        )
    }

    // MARK: - Doing it

    /// Deletes `assignment`, keeping its notes on the children, the text of
    /// its history rows, and every mastery mark filed on it.
    static func delete(_ assignment: CDLessonAssignment, in context: NSManagedObjectContext) {
        ChecklistRosterRemoval.keepMasteryMarks(on: assignment, studentIDs: nil, in: context)
        keepNotesOnChildren(of: assignment, in: context)
        keepHistoryText(of: assignment, in: context)
        detachWork(from: assignment, in: context)
        PresentationRecordCleanup.prepareToDelete(assignment, in: context)
        context.delete(assignment)
    }

    /// Takes `studentID` off `assignment` as the Checklist's Remove Plan does
    /// (`ChecklistRosterRemoval`): her promoted entries go back to planned and
    /// her marks stay. When she was the last child the plan goes, its notes
    /// kept as hers first. Returns whether the plan went.
    @discardableResult
    static func remove(
        _ studentID: String, from assignment: CDLessonAssignment, in context: NSManagedObjectContext
    ) -> Bool {
        let emptied = emptiedByRemoving(studentID, from: assignment)
        // The history rows' text is kept by `ChecklistRosterRemoval.remove`
        // itself; keeping it here too made every note twice.
        if emptied {
            keepNotesOnChildren(of: assignment, in: context)
        }
        ChecklistRosterRemoval.remove(studentID, from: assignment, in: context)
        if !emptied {
            assignment.updateDenormalizedKeys()
            assignment.modifiedAt = Date()
        }
        return emptied
    }

    // MARK: - Pieces

    /// The presentation's work stays, as the children's own follow-up work,
    /// rather than pointing at a presentation that no longer exists.
    static func detachWork(from assignment: CDLessonAssignment, in context: NSManagedObjectContext) {
        guard let id = assignment.id?.uuidString else { return }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID ==[c] %@", id)
        for work in context.safeFetch(request) where !work.isDeleted {
            work.presentationID = nil
        }
    }

    private static func emptiedByRemoving(_ studentID: String, from assignment: CDLessonAssignment) -> Bool {
        assignment.studentIDs.allSatisfy { $0 == studentID }
    }

    /// Every note on `assignment` comes off it and stays with the children it
    /// was about. A note for the whole group (scope "all") names every child on
    /// the presentation: left as it was, it would read as a note on the whole
    /// class. A note that named no lesson is filed under this one.
    static func keepNotesOnChildren(of assignment: CDLessonAssignment, in context: NSManagedObjectContext) {
        let children = assignment.resolvedStudentIDs
        let lessonKey = lessonKey(of: assignment)
        for note in (assignment.unifiedNotes as? Set<CDNote>) ?? [] where !note.isDeleted {
            note.lessonAssignment = nil
            if case .all = note.scope, let only = children.first {
                note.scope = children.count == 1 ? .student(only) : .students(children)
                note.syncStudentLinks(in: context)
            }
            if (note.lessonID ?? "").isEmpty, !lessonKey.isEmpty { note.lessonID = lessonKey }
            note.updatedAt = Date()
        }
    }

    /// The text of each history row that goes with the presentation (its notes
    /// and follow-up note), kept as a note on its child, dated as the row was.
    /// Rows carrying a mastery mark are kept whole, so call after
    /// `keepMasteryMarks` has unlinked them.
    static func keepHistoryText(of assignment: CDLessonAssignment, in context: NSManagedObjectContext) {
        guard let id = assignment.id?.uuidString else { return }
        let lessonKey = lessonKey(of: assignment)
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "presentationID == %@", id)
        for row in context.safeFetch(request) where !row.isDeleted {
            let text = [row.notes, row.followUpNote]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            guard !text.isEmpty, let studentID = UUID(uuidString: row.studentID) else { continue }
            let note = CDNote(context: context)
            note.body = text
            note.createdAt = row.presentedAt ?? row.createdAt ?? Date()
            note.updatedAt = note.createdAt
            note.scope = .student(studentID)
            note.lessonID = lessonKey.isEmpty ? row.lessonID : lessonKey
        }
    }

    private static func lessonKey(of assignment: CDLessonAssignment) -> String {
        UUID(uuidString: assignment.lessonID)?.uuidString ?? assignment.lessonID
    }

    /// "Maya S", "Maya S and Ada L", or "the children" for many or none.
    private static func children(_ names: [String]) -> String {
        let names = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !names.isEmpty, names.count <= 3 else { return "the children" }
        return ListFormatter.localizedString(byJoining: names)
    }

    /// "Its note stays on Maya S." / "Its 3 notes stay on the children."
    private static func notesLine(_ count: Int, who: String) -> String? {
        switch count {
        case ...0: nil
        case 1: "Its note stays on \(who)."
        default: "Its \(count) notes stay on \(who)."
        }
    }
}
