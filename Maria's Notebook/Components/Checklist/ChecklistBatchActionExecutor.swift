import Foundation
import OSLog
import CoreData

// MARK: - Checklist Batch Action Executor

/// Executes batch operations on checklist cells.
/// Handles adding to inbox, marking presented/mastered, and clearing status.
@MainActor
// swiftlint:disable:next type_body_length
enum ChecklistBatchActionExecutor {
    private static let logger = Logger.lessons

    // MARK: - Batch Add to Inbox

    /// Adds selected cells to inbox (creates draft LessonAssignments).
    static func batchAddToInbox(
        selectedCells: Set<CellIdentifier>,
        students: [CDStudent],
        lessons: [CDLesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: NSManagedObjectContext
    ) {
        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            // Only add if not already scheduled
            if state?.isScheduled != true {
                toggleScheduledNoRecompute(student: student, lesson: lesson, context: context)
            }
        }
        context.safeSave()
    }

    // MARK: - Batch Mark Presented

    /// Marks selected cells as presented.
    static func batchMarkPresented(
        selectedCells: Set<CellIdentifier>,
        students: [CDStudent],
        lessons: [CDLesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: NSManagedObjectContext
    ) {
        // Pre-fetch all LessonPresentations once for upsert operations
        let allLPs = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))

        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            if state?.isPresented != true {
                togglePresentedNoRecompute(
                    student: student, lesson: lesson,
                    prefetchedLPs: allLPs, context: context
                )
            }
        }
        context.safeSave()
    }

    // MARK: - Batch Mark Previously Presented

    /// Marks selected cells as previously presented (undated).
    static func batchMarkPreviouslyPresented(
        selectedCells: Set<CellIdentifier>,
        students: [CDStudent],
        lessons: [CDLesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: NSManagedObjectContext
    ) {
        let allLPs = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))

        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            if state?.isPresented != true {
                togglePreviouslyPresentedNoRecompute(
                    student: student, lesson: lesson,
                    prefetchedLPs: allLPs, context: context
                )
            }
        }
        context.safeSave()
    }

    // MARK: - Batch Mark Mastered

    /// Marks selected cells as mastered/complete.
    static func batchMarkProficient(
        selectedCells: Set<CellIdentifier>,
        students: [CDStudent],
        lessons: [CDLesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: NSManagedObjectContext
    ) {
        // Pre-fetch shared data once before the loop
        let allWorkModels = context.safeFetch(CDFetchRequest(CDWorkModel.self))
        let allLPs = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))

        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            if state?.isComplete != true {
                markCompleteNoRecompute(
                    student: student, lesson: lesson,
                    prefetchedWorkModels: allWorkModels,
                    prefetchedLPs: allLPs,
                    context: context
                )
            }
        }
        context.safeSave()
    }

    // MARK: - Batch Clear Status

    /// Clears all status from selected cells.
    static func batchClearStatus(
        selectedCells: Set<CellIdentifier>,
        students: [CDStudent],
        lessons: [CDLesson],
        context: NSManagedObjectContext
    ) {
        // Pre-fetch shared data once before the loop
        let allWorkModels = context.safeFetch(CDFetchRequest(CDWorkModel.self))
        let allLPs = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))

        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            clearStatusNoRecompute(
                student: student, lesson: lesson,
                prefetchedWorkModels: allWorkModels,
                prefetchedLPs: allLPs,
                context: context
            )
        }
        context.safeSave()
    }

    // MARK: - Private Helpers

    private static func toggleScheduledNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        let lessonIDString = lesson.id?.uuidString ?? ""
        let studentIDString = student.cloudKitKey

        let laRequest = CDFetchRequest(CDLessonAssignment.self)
        laRequest.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
        let allLAs = context.safeFetch(laRequest)

        if let existing = allLAs.first(where: {
            !$0.isPresented && $0.studentIDs.contains(studentIDString)
        }) {
            var ids = existing.studentIDs
            ids.removeAll { $0 == studentIDString }
            if ids.isEmpty {
                context.delete(existing)
            } else {
                existing.studentIDs = ids
            }
        } else {
            if let group = allLAs.first(where: { !$0.isPresented && $0.scheduledFor == nil }) {
                if !group.studentIDs.contains(studentIDString) {
                    group.studentIDs.append(studentIDString)
                }
            } else {
                guard let lessonID = lesson.id, let studentID = student.id else { return }
                PresentationFactory.insertDraft(
                    lessonID: lessonID,
                    studentIDs: [studentID],
                    context: context
                )
            }
        }
    }

    private static func togglePresentedNoRecompute(
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
            addStudentToGivenLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
            upsertLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString,
                state: .presented, from: prefetchedLPs, context: context
            )
        }
    }

    private static func markCompleteNoRecompute(
        student: CDStudent, lesson: CDLesson,
        prefetchedWorkModels: [CDWorkModel],
        prefetchedLPs: [CDLessonPresentation],
        context: NSManagedObjectContext
    ) {
        let studentIDString = student.cloudKitKey
        let lessonIDString = lesson.id?.uuidString ?? ""

        let laRequest = CDFetchRequest(CDLessonAssignment.self)
        laRequest.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
        let allLAs = context.safeFetch(laRequest)
        if allLAs.first(where: { $0.isPresented && $0.studentIDs.contains(studentIDString) }) == nil {
            addStudentToGivenLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
        }

        findOrCreateWorkAndMarkComplete(
            student: student, lesson: lesson,
            prefetchedWorkModels: prefetchedWorkModels, context: context
        )

        upsertLessonPresentation(
            studentID: studentIDString, lessonID: lessonIDString,
            state: .proficient, from: prefetchedLPs, context: context
        )

        GroupTrackService.autoEnrollInTrackIfNeeded(
            lessonSubject: lesson.subject, lessonGroup: lesson.group,
            studentIDs: [studentIDString], context: context
        )
        GroupTrackService.checkAndCompleteTrackIfNeeded(
            lessonSubject: lesson.subject, lessonGroup: lesson.group,
            studentID: studentIDString, context: context
        )
    }

    private static func clearStatusNoRecompute(
        student: CDStudent, lesson: CDLesson,
        prefetchedWorkModels: [CDWorkModel],
        prefetchedLPs: [CDLessonPresentation],
        context: NSManagedObjectContext
    ) {
        let sidString = student.cloudKitKey
        let lidString = lesson.id?.uuidString ?? ""

        let lasRequest = CDFetchRequest(CDLessonAssignment.self)
        lasRequest.predicate = NSPredicate(format: "lessonID == %@", lidString as CVarArg)
        let las = context.safeFetch(lasRequest)
        for la in las where la.studentIDs.contains(sidString) {
            var newIDs = la.studentIDs
            newIDs.removeAll { $0 == sidString }
            if newIDs.isEmpty {
                context.delete(la)
            } else {
                la.studentIDs = newIDs
            }
        }

        // Filter from pre-fetched WorkModels instead of re-fetching all
        let workModelsToDelete = prefetchedWorkModels.filter { work in
            guard work.lessonID == lidString else { return false }
            let parts = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
            return parts.contains { $0.studentID == sidString }
        }
        for work in workModelsToDelete {
            context.delete(work)
        }

        deleteLessonPresentation(
            studentID: sidString, lessonID: lidString,
            from: prefetchedLPs, context: context
        )
    }

    private static func addStudentToGivenLesson(
        student: CDStudent,
        studentIDString: String,
        lesson: CDLesson,
        in allLAs: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) {
        let today = Date()
        if let group = allLAs.first(where: {
            $0.isPresented && ($0.presentedAt ?? Date.distantPast).isSameDay(as: today)
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
            PresentationFactory.insertPresented(
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

    private static func findOrCreateWorkAndMarkComplete(
        student: CDStudent, lesson: CDLesson,
        prefetchedWorkModels: [CDWorkModel],
        context: NSManagedObjectContext
    ) {
        guard let sid = student.id, let lid = lesson.id else { return }
        let lidString = lid.uuidString

        // Filter from pre-fetched data instead of re-fetching all WorkModels
        if let existingWork = prefetchedWorkModels.first(where: { work in
            guard work.lessonID == lidString else { return false }
            let parts = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
            return parts.contains { $0.studentID == sid.uuidString }
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
                title: nil,
                kind: nil,
                presentationID: nil,
                scheduledDate: nil
            )
            work.status = .complete
            work.completedAt = AppCalendar.startOfDay(Date())
        } catch {
            logger.warning("Failed to create work: \(error)")
        }
    }

    static func upsertLessonPresentation(
        studentID: String,
        lessonID: String,
        state: LessonPresentationState,
        from prefetchedLPs: [CDLessonPresentation],
        context: NSManagedObjectContext
    ) {
        // Filter from pre-fetched data instead of re-fetching all LessonPresentations
        let existing = prefetchedLPs.first { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }

        if let existing {
            if state == .proficient && existing.state != .proficient {
                existing.state = .proficient
                existing.masteredAt = Date()
            }
            existing.lastObservedAt = Date()
        } else {
            let lp = CDLessonPresentation(context: context)
            lp.studentID = studentID
            lp.lessonID = lessonID
            lp.state = state
            lp.presentedAt = Date()
            lp.lastObservedAt = Date()
            lp.masteredAt = state == .proficient ? Date() : nil
        }
    }

}
