// ClassAreaChecklistViewModel+Presenting.swift
// The card's "Present with N others ready…" and the selection bar's "Present as a
// group…": a draft presentation for exactly those children, made the way the
// Three-Year View makes one, for the present-a-lesson sheet to record. Recording
// takes the children off any other plan for the lesson (the sheet's own rule), so
// nothing here moves them. A draft the sheet closes without recording or
// scheduling is discarded, so a look at the sheet leaves no stray Inbox entry.

import Foundation
import CoreData

extension ClassAreaChecklistViewModel {

    /// The card's child first, then the other children ready for the lesson, in column order.
    func presentationStudentIDs(for cell: CellIdentifier, studentOrder: [UUID]) -> [UUID] {
        [cell.studentID] + readyStudentIDs(for: cell.lessonID, studentOrder: studentOrder, excluding: cell.studentID)
    }

    /// A saved draft presentation of `lessonID` for `studentIDs`, or nil when the lesson
    /// or every child is missing.
    func makePresentationDraft(
        lessonID: UUID, studentIDs: [UUID], context: NSManagedObjectContext
    ) -> CDLessonAssignment? {
        guard let lesson = lessons.first(where: { $0.id == lessonID }) else { return nil }
        let chosen = studentIDs.compactMap { id in rosterStudents.first { $0.id == id } }
        guard !chosen.isEmpty else { return nil }
        let draft = PresentationFactory.makeDraft(lesson: lesson, students: chosen, context: context)
        draft.syncSnapshotsFromRelationships()
        context.safeSave()
        return draft
    }

    /// After the sheet closes: a draft it neither recorded nor scheduled goes away again.
    func discardUnusedDraft(_ draft: CDLessonAssignment, context: NSManagedObjectContext) {
        guard draft.managedObjectContext != nil, !draft.isDeleted,
              !draft.isPresented, !draft.isScheduled
        else { return }
        PresentationRecordCleanup.prepareToDelete(draft, in: context)
        context.delete(draft)
        context.safeSave()
    }
}
