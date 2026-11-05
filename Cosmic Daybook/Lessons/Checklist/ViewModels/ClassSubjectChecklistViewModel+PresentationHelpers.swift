// ClassAreaChecklistViewModel+PresentationHelpers.swift
// CDLessonPresentation upsert helper for ClassAreaChecklistViewModel. A cell's work for
// Mastered and its Clear live in `ChecklistCellRecords`, shared with the selection bar.

import Foundation
import OSLog
import CoreData

extension ClassAreaChecklistViewModel {

    // MARK: - CDLessonPresentation Helpers

    /// Files the mark on her latest history row for the lesson, or makes one dated
    /// `givenOn` (the presentation's date; nil for an undated one), by the selection's
    /// own rule (`ChecklistBatchActionExecutor.upsertLessonPresentation`).
    func upsertLessonPresentation(
        studentID: String, lessonID: String,
        state: LessonPresentationState, givenOn: Date?, context: NSManagedObjectContext
    ) {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "studentID == %@ AND lessonID == %@", studentID, lessonID)
        ChecklistBatchActionExecutor.upsertLessonPresentation(
            studentID: studentID, lessonID: lessonID, state: state,
            from: context.safeFetch(request), givenOn: givenOn, context: context
        )
    }
}
