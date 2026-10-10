// ClassAreaChecklistViewModel+PresentationHelpers.swift
// CDLessonPresentation upsert helper for ClassAreaChecklistViewModel. A cell's work for
// Mastered and its Clear live in `ChecklistCellRecords`, shared with the selection bar.

import Foundation
import OSLog
import CoreData

extension ClassAreaChecklistViewModel {

    // MARK: - CDLessonPresentation Helpers

    func upsertLessonPresentation(
        studentID: String, lessonID: String,
        state: LessonPresentationState, context: NSManagedObjectContext
    ) {
        // OPTIMIZATION: Use predicate to fetch only the specific presentation instead of all
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "studentID == %@ AND lessonID == %@", studentID, lessonID)
        request.fetchLimit = 1
        let existing = context.safeFetchFirst(request)

        if let existing {
            if state == .proficient && existing.state != .proficient {
                existing.state = .proficient
                existing.masteredAt = Date()
            }
            existing.lastObservedAt = Date()
        } else {
            let lp = CDLessonPresentation(context: context)
            lp.id = UUID()
            lp.studentID = studentID
            lp.lessonID = lessonID
            lp.state = state
            lp.presentedAt = Date()
            lp.lastObservedAt = Date()
            lp.masteredAt = state == .proficient ? Date() : nil
        }
    }
}
