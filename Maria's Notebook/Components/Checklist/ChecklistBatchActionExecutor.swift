import Foundation
import OSLog
import SwiftData

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
        students: [Student],
        lessons: [Lesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: ModelContext
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
        students: [Student],
        lessons: [Lesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: ModelContext
    ) {
        // Pre-fetch all LessonPresentations once for upsert operations
        let allLPs = context.safeFetch(FetchDescriptor<LessonPresentation>())

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
        students: [Student],
        lessons: [Lesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: ModelContext
    ) {
        let allLPs = context.safeFetch(FetchDescriptor<LessonPresentation>())

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
        students: [Student],
        lessons: [Lesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: ModelContext
    ) {
        // Pre-fetch shared data once before the loop
        let allWorkModels = context.safeFetch(FetchDescriptor<WorkModel>())
        let allLPs = context.safeFetch(FetchDescriptor<LessonPresentation>())

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
        students: [Student],
        lessons: [Lesson],
        context: ModelContext
    ) {
        // Pre-fetch shared data once before the loop
        let allWorkModels = context.safeFetch(FetchDescriptor<WorkModel>())
        let allLPs = context.safeFetch(FetchDescriptor<LessonPresentation>())

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

    private static func toggleScheduledNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lessonIDString = lesson.id.uuidString
        let studentIDString = student.cloudKitKey

        let allLAs = context.safeFetch(
            FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.lessonID == lessonIDString })
        )

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
                _ = PresentationFactory.insertDraft(
                    lessonID: lesson.id,
                    studentIDs: [student.id],
                    context: context
                )
            }
        }
    }

    private static func togglePresentedNoRecompute(
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
        student: Student, lesson: Lesson,
        prefetchedWorkModels: [WorkModel],
        prefetchedLPs: [LessonPresentation],
        context: ModelContext
    ) {
        let studentIDString = student.cloudKitKey
        let lessonIDString = lesson.id.uuidString

        let allLAs = context.safeFetch(
            FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.lessonID == lessonIDString })
        )
        if allLAs.first(where: { $0.isPresented && $0.studentIDs.contains(studentIDString) }) == nil {
            addStudentToGivenLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
        }

        if let work = findOrCreateWork(
            student: student, lesson: lesson,
            prefetchedWorkModels: prefetchedWorkModels, context: context
        ) {
            work.status = .complete
            work.completedAt = AppCalendar.startOfDay(Date())
        }

        upsertLessonPresentation(
            studentID: studentIDString, lessonID: lessonIDString,
            state: .proficient, from: prefetchedLPs, context: context
        )

        GroupTrackService.autoEnrollInTrackIfNeeded(
            lesson: lesson, studentIDs: [studentIDString], modelContext: context
        )
        GroupTrackService.checkAndCompleteTrackIfNeeded(
            lesson: lesson, studentID: studentIDString, modelContext: context
        )
    }

    private static func clearStatusNoRecompute(
        student: Student, lesson: Lesson,
        prefetchedWorkModels: [WorkModel],
        prefetchedLPs: [LessonPresentation],
        context: ModelContext
    ) {
        let sidString = student.cloudKitKey
        let lidString = lesson.id.uuidString

        let las = context.safeFetch(
            FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.lessonID == lidString })
        )
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
            return (work.participants ?? []).contains { $0.studentID == sidString }
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
        student: Student,
        studentIDString: String,
        lesson: Lesson,
        in allLAs: [LessonAssignment],
        context: ModelContext
    ) {
        let today = Date()
        if let group = allLAs.first(where: {
            $0.isPresented && ($0.presentedAt ?? Date.distantPast).isSameDay(as: today)
        }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lesson: lesson, studentIDs: [studentIDString], modelContext: context
                )
            }
        } else {
            _ = PresentationFactory.insertPresented(
                lessonID: lesson.id,
                studentIDs: [student.id],
                context: context
            )
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: lesson, studentIDs: [studentIDString], modelContext: context
            )
        }
    }

    private static func findOrCreateWork(
        student: Student, lesson: Lesson,
        prefetchedWorkModels: [WorkModel],
        context: ModelContext
    ) -> WorkModel? {
        let sid = student.id
        let lidString = lesson.id.uuidString

        // Filter from pre-fetched data instead of re-fetching all WorkModels
        let existingWork = prefetchedWorkModels.first { work in
            guard work.lessonID == lidString else { return false }
            return (work.participants ?? []).contains { $0.studentID == sid.uuidString }
        }

        if let existing = existingWork {
            return existing
        }

        let repository = WorkRepository(context: context)
        do {
            return try repository.createWork(
                studentID: sid,
                lessonID: lesson.id,
                title: nil,
                kind: nil,
                presentationID: nil,
                scheduledDate: nil
            )
        } catch {
            logger.warning("Failed to create work: \(error)")
            return nil
        }
    }

    private static func upsertLessonPresentation(
        studentID: String,
        lessonID: String,
        state: LessonPresentationState,
        from prefetchedLPs: [LessonPresentation],
        context: ModelContext
    ) {
        // Filter from pre-fetched data instead of re-fetching all LessonPresentations
        let existing = prefetchedLPs.first { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }

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

    private static func deleteLessonPresentation(
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

    // MARK: - Previously Presented Helpers

    private static func togglePreviouslyPresentedNoRecompute(
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

    private static func addStudentToUndatedLesson(
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
            _ = PresentationFactory.insertPreviouslyPresented(
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
