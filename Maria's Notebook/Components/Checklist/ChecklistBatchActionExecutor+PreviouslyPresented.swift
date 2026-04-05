import Foundation
import OSLog
import CoreData

// MARK: - Previously Presented Helpers

@MainActor
extension ChecklistBatchActionExecutor {

    static func deleteLessonPresentation(
        studentID: String, lessonID: String,
        from prefetchedLPs: [CDLessonPresentation],
        context: NSManagedObjectContext
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
        student: CDStudent, lesson: CDLesson,
        prefetchedLPs: [CDLessonPresentation],
        context: NSManagedObjectContext
    ) {
        let studentIDString = student.cloudKitKey
        let lessonIDString = lesson.id?.uuidString ?? ""

        let laRequest = CDFetchRequest(CDLessonAssignment.self)
        laRequest.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
        let allLAs = context.safeFetch(laRequest)

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
        student: CDStudent,
        studentIDString: String,
        lesson: CDLesson,
        in allLAs: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) {
        if let group = allLAs.first(where: {
            $0.isPresented && $0.presentedAt == nil
        }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lessonSubject: lesson.subject, lessonGroup: lesson.group,
                    studentIDs: [studentIDString], context: context
                )
            }
        } else {
            guard let lessonID = lesson.id, let studentID = student.id else { return }
            _ = PresentationFactory.makePreviouslyPresented(
                lessonID: lessonID,
                studentIDs: [studentID],
                context: context
            )
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lessonSubject: lesson.subject, lessonGroup: lesson.group,
                studentIDs: [studentIDString], context: context
            )
        }
    }
}
