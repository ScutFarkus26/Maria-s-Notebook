// ClassSubjectChecklistViewModel+PresentationHelpers.swift
// WorkModel find-or-create and LessonPresentation upsert/delete helpers
// for ClassSubjectChecklistViewModel.

import Foundation
import OSLog
import SwiftData

extension ClassSubjectChecklistViewModel {

    // MARK: - Work Model Helpers

    func findOrCreateWork(student: Student, lesson: Lesson, context: ModelContext) -> WorkModel? {
        let sid = student.id
        let lid = lesson.id
        let lidString = lid.uuidString

        // OPTIMIZATION: Fetch only non-complete work since we're looking for active/review work
        let workDescriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { $0.statusRaw != "complete" }
        )
        let allWorkModels = context.safeFetch(workDescriptor)

        let existingWork = allWorkModels.first { work in
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sid.uuidString }
            guard hasStudent else { return false }
            return work.lessonID == lidString
        }

        if let existing = existingWork {
            return existing
        }

        let repository = WorkRepository(context: context)
        do {
            return try repository.createWork(
                studentID: sid,
                lessonID: lid,
                title: nil,
                kind: nil,
                presentationID: nil,
                scheduledDate: nil
            )
        } catch {
            Self.logger.warning("Failed to create work for student \(sid): \(error)")
            return nil
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

        if let existing = existing {
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
