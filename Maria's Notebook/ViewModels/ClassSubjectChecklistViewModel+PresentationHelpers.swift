// ClassSubjectChecklistViewModel+PresentationHelpers.swift
// CDWorkModel find-or-create and CDLessonPresentation upsert/delete helpers
// for ClassSubjectChecklistViewModel.

import Foundation
import OSLog
import CoreData

extension ClassSubjectChecklistViewModel {

    // MARK: - Work Model Helpers

    /// Finds existing work or creates new one, and marks it complete.
    func findOrCreateWorkAndMarkComplete(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let sid = student.id, let lid = lesson.id else { return }
        let lidString = lid.uuidString

        // PERF: Filter by lessonID in predicate to avoid loading all non-complete work.
        let workRequest = CDFetchRequest(CDWorkModel.self)
        workRequest.predicate = NSPredicate(format: "statusRaw != %@ AND lessonID == %@", "complete", lidString)
        let matchingWorkModels = context.safeFetch(workRequest)

        if let existingWork = matchingWorkModels.first(where: { work in
            ((work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []).contains { $0.studentID == sid.uuidString }
        }) {
            existingWork.status = .complete
            existingWork.completedAt = AppCalendar.startOfDay(Date())
            return
        }

        let repository = WorkRepository(context: context)
        do {
            let work = try repository.createWork(
                studentID: sid,
                lessonID: lid,
                title: nil as String?,
                kind: nil as WorkKind?,
                presentationID: nil as UUID?,
                scheduledDate: nil as Date?
            )
            work.status = .complete
            work.completedAt = AppCalendar.startOfDay(Date())
        } catch {
            Self.logger.warning("Failed to create work for student \(sid): \(error)")
        }
    }

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

    func deleteLessonPresentation(studentID: String, lessonID: String, context: NSManagedObjectContext) {
        // OPTIMIZATION: Use predicate to fetch only the specific presentations to delete
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "studentID == %@ AND lessonID == %@", studentID, lessonID)
        let toDelete = context.safeFetch(request)
        for lp in toDelete {
            context.delete(lp)
        }
    }
}
