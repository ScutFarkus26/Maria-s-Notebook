// ClassSubjectChecklistViewModel+PresentationHelpers.swift
// WorkModel find-or-create and LessonPresentation upsert/delete helpers
// for ClassSubjectChecklistViewModel.

import Foundation
import OSLog
import SwiftData

extension ClassSubjectChecklistViewModel {

    // MARK: - Work Model Helpers

    /// Finds existing work or creates new one, and marks it complete.
    func findOrCreateWorkAndMarkComplete(student: Student, lesson: Lesson, context: ModelContext) {
        let sid = student.id
        let lid = lesson.id
        let lidString = lid.uuidString

        // PERF: Filter by lessonID in predicate to avoid loading all non-complete work.
        let workDescriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { $0.statusRaw != "complete" && $0.lessonID == lidString }
        )
        let matchingWorkModels = context.safeFetch(workDescriptor)

        if let existingWork = matchingWorkModels.first(where: { work in
            (work.participants ?? []).contains { $0.studentID == sid.uuidString }
        }) {
            existingWork.status = .complete
            existingWork.completedAt = AppCalendar.startOfDay(Date())
            return
        }

        let repository = WorkRepository(modelContext: context)
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

    // MARK: - LessonPresentation Helpers

    func upsertLessonPresentation(
        studentID: String, lessonID: String,
        state: LessonPresentationState, context: ModelContext
    ) {
        // OPTIMIZATION: Use predicate to fetch only the specific presentation instead of all
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate<LessonPresentation> { $0.studentID == studentID && $0.lessonID == lessonID }
        )
        let existing = context.safeFetch(descriptor).first

        if let existing {
            if state == .proficient && existing.state != .proficient {
                existing.state = .proficient
                existing.masteredAt = Date()
            }
            existing.lastObservedAt = Date()
        } else {
            let lp = LessonPresentation(
                studentID: studentID,
                lessonID: lessonID,
                presentationID: nil,
                state: state,
                presentedAt: Date(),
                lastObservedAt: Date(),
                masteredAt: state == .proficient ? Date() : nil
            )
            context.insert(lp)
        }
    }

    func deleteLessonPresentation(studentID: String, lessonID: String, context: ModelContext) {
        // OPTIMIZATION: Use predicate to fetch only the specific presentations to delete
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate<LessonPresentation> { $0.studentID == studentID && $0.lessonID == lessonID }
        )
        let toDelete = context.safeFetch(descriptor)
        for lp in toDelete {
            context.delete(lp)
        }
    }
}
