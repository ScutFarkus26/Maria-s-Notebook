//
//  ChecklistRosterRemoval.swift
//  Cosmic Daybook
//
//  Taking one child off a plan or presentation from the checklist: Remove Plan,
//  Remove from Inbox, and Unmark Presented. It goes through
//  `PresentationRecordCleanup`, so her promoted year-plan entries go back to
//  planned and the presentation's history rows for her go, but a mastery mark
//  never does; one filed on the presentation's row is kept as a mark of its own.
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
            PresentationRecordCleanup.prepareToDelete(assignment, in: context)
            context.delete(assignment)
        } else {
            keepMasteryMarks(on: assignment, studentIDs: [studentID], in: context)
            PresentationRecordCleanup.removeStudents([studentID], from: assignment, in: context)
            assignment.studentIDs = ids
        }
    }

    /// After Unmark Presented took her off `unmarked`: once she is on no other presented
    /// row for the lesson, the plain row the Presented toggle made goes too (no
    /// presentation, state Presented, no mark). Rows of other presentations, the guide's
    /// practicing or ready-for-assessment states, and every mastery mark stay.
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
        for row in context.safeFetch(request) where !row.isDeleted {
            context.delete(row)
        }
    }

    /// Mastery marks on the presentation's rows lose their link to it, so the cleanup that
    /// follows (which deletes the presentation's rows) leaves them standing.
    private static func keepMasteryMarks(
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
}
