//
//  ChecklistRosterRemoval.swift
//  Cosmic Daybook
//
//  Taking one child off a plan or presentation from the checklist: Remove Plan,
//  Remove from Inbox, and Unmark Presented. It goes through
//  `PresentationRecordCleanup`, so her promoted year-plan entries go back to
//  planned and the presentation's history rows for her go, but a mastery mark
//  never does; one filed on the presentation's row is kept as a mark of its own.
//
//  What was written stays, as Clear keeps it (`ChecklistCellRecords`): when she
//  was the last child on the record and it goes, its notes come off it first
//  and stay in her notes, and the text of the history rows that go with it is
//  kept as a note on her, filed under the lesson. One click used to delete them
//  with the record (bug hunt 2026-11-03 #2); the Checklist now also asks first
//  (`removalSummary`, `ChecklistRemovalRequest`).
//
//  None of these saves; the caller owns the save.
//

import CoreData
import Foundation

enum ChecklistRosterRemoval {

    /// Takes `studentID` off `assignment`, deleting the assignment when she was the last
    /// child on it.
    static func remove(
        _ studentID: String, from assignment: CDLessonAssignment, in context: NSManagedObjectContext
    ) {
        var ids = assignment.studentIDs
        ids.removeAll { $0 == studentID }
        if ids.isEmpty {
            keepMasteryMarks(on: assignment, studentIDs: nil, in: context)
            ChecklistCellRecords.keepText(of: rowsLeaving(assignment, studentIDs: nil, in: context), in: context)
            ChecklistCellRecords.keepNotes(
                onPresentationLeaving: assignment, for: UUID(uuidString: studentID),
                lessonKey: assignment.lessonID, in: context
            )
            PresentationRecordCleanup.prepareToDelete(assignment, in: context)
            context.delete(assignment)
        } else {
            keepMasteryMarks(on: assignment, studentIDs: [studentID], in: context)
            ChecklistCellRecords.keepText(
                of: rowsLeaving(assignment, studentIDs: [studentID], in: context), in: context
            )
            PresentationRecordCleanup.removeStudents([studentID], from: assignment, in: context)
            assignment.studentIDs = ids
        }
    }

    /// What `remove` would delete when it deletes the record: nil when other children stay
    /// on it, or she isn't on it. Touches nothing.
    static func removalSummary(
        of studentID: String, from assignment: CDLessonAssignment, in context: NSManagedObjectContext
    ) -> ChecklistRemovalSummary? {
        guard assignment.studentIDs.contains(studentID),
              assignment.studentIDs.allSatisfy({ $0 == studentID }) else { return nil }
        let rows = rowsLeaving(assignment, studentIDs: nil, in: context).filter { !isMasteryMark($0) }
        return ChecklistRemovalSummary(
            wasGiven: assignment.isPresented,
            givenOn: assignment.isPresented ? assignment.presentedAt : nil,
            noteCount: ChecklistCellRecords.noteCount(on: assignment, rows: rows)
        )
    }

    /// After Unmark Presented took her off `unmarked`: once she is on no other presented
    /// row for the lesson, the plain row the Presented toggle made goes too (no
    /// presentation, state Presented, no mark), its text kept as a note on her. Rows of
    /// other presentations, the guide's practicing or ready-for-assessment states, and
    /// every mastery mark stay.
    static func deleteToggleHistory(
        studentID: String, lessonID: String,
        unmarked: CDLessonAssignment, among assignments: [CDLessonAssignment],
        in context: NSManagedObjectContext
    ) {
        let stillPresented = assignments.contains {
            $0 !== unmarked && !$0.isDeleted && $0.isPresented && $0.studentIDs.contains(studentID)
        }
        guard !stillPresented else { return }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND lessonID == %@ AND presentationID == nil"
                + " AND masteredAt == nil AND stateRaw == %@",
            studentID, lessonID, LessonPresentationState.presented.rawValue
        )
        let rows = context.safeFetch(request).filter { !$0.isDeleted }
        ChecklistCellRecords.keepText(of: rows, in: context)
        for row in rows {
            context.delete(row)
        }
    }

    /// Mastery marks on the presentation's rows lose their link to it, so the cleanup that
    /// follows (which deletes the presentation's rows) leaves them standing. Also used by
    /// `LessonDeletion` for the planned presentations a lesson delete removes.
    static func keepMasteryMarks(
        on assignment: CDLessonAssignment, studentIDs: Set<String>?, in context: NSManagedObjectContext
    ) {
        guard let id = assignment.id?.uuidString else { return }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@ AND (masteredAt != nil OR stateRaw == %@)",
            id, LessonPresentationState.proficient.rawValue
        )
        for row in context.safeFetch(request) where !row.isDeleted {
            if let studentIDs, !studentIDs.contains(row.studentID) { continue }
            row.presentationID = nil
        }
    }

    // MARK: - Pieces

    /// The presentation's history rows (only these children's, when given), which its
    /// cleanup deletes once `keepMasteryMarks` has unlinked the marks.
    private static func rowsLeaving(
        _ assignment: CDLessonAssignment, studentIDs: Set<String>?, in context: NSManagedObjectContext
    ) -> [CDLessonPresentation] {
        guard let id = assignment.id?.uuidString else { return [] }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "presentationID == %@", id)
        return context.safeFetch(request).filter { row in
            !row.isDeleted && (studentIDs.map { $0.contains(row.studentID) } ?? true)
        }
    }

    private static func isMasteryMark(_ row: CDLessonPresentation) -> Bool {
        row.masteredAt != nil || row.state == .proficient
    }
}
