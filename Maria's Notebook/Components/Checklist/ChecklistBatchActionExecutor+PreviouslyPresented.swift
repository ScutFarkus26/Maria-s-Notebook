import Foundation
import OSLog
import SwiftData

// MARK: - Previously Presented Helpers

@MainActor
extension ChecklistBatchActionExecutor {

    static func deleteLessonPresentation(
        studentID: String, lessonID: String,
        from prefetchedLPs: [LessonPresentation],
        context: ModelContext
    ) {
        // Filter from pre-fetched data instead of re-fetching all LessonPresentations
        let toDelete = prefetchedLPs.filter { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }
        for lp in toDelete {
            context.delete(lp)
        }
    }

    static func togglePreviouslyPresentedNoRecompute(
        student: Student, lesson: Lesson,
        prefetchedLPs: [LessonPresentation],
        context: ModelContext
    ) {
        let studentIDString = student.cloudKitKey
        let lessonIDString = lesson.id.uuidString

        let allLAs = context.safeFetch(
            FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.lessonID == lessonIDString })
        )

        if let existing = allLAs.first(where: {
            $0.isPresented && $0.studentIDs.contains(studentIDString)
        }) {
            var ids = existing.studentIDs
            ids.removeAll { $0 == studentIDString }
            if ids.isEmpty {
                context.delete(existing)
            } else {
                existing.studentIDs = ids
            }
            deleteLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString,
                from: prefetchedLPs, context: context
            )
        } else {
            addStudentToUndatedLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
            upsertLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString,
                state: .presented, from: prefetchedLPs, context: context
            )
        }
    }

    static func addStudentToUndatedLesson(
        student: Student,
        studentIDString: String,
        lesson: Lesson,
        in allLAs: [LessonAssignment],
        context: ModelContext
    ) {
        if let group = allLAs.first(where: {
            $0.isPresented && $0.presentedAt == nil
        }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lesson: lesson, studentIDs: [studentIDString], modelContext: context
                )
            }
        } else {
            PresentationFactory.insertPreviouslyPresented(
                lessonID: lesson.id,
                studentIDs: [student.id],
                context: context
            )
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: lesson, studentIDs: [studentIDString], modelContext: context
            )
        }
    }
}
