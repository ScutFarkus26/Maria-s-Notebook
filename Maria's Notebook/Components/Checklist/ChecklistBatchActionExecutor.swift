import Foundation
import SwiftData

// MARK: - Checklist Batch Action Executor

/// Executes batch operations on checklist cells.
/// Handles adding to inbox, marking presented/mastered, and clearing status.
enum ChecklistBatchActionExecutor {

    // MARK: - Batch Add to Inbox

    /// Adds selected cells to inbox (creates unscheduled StudentLessons).
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
        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            // Only mark presented if not already presented
            if state?.isPresented != true {
                togglePresentedNoRecompute(student: student, lesson: lesson, context: context)
            }
        }
        context.safeSave()
    }

    // MARK: - Batch Mark Mastered

    /// Marks selected cells as mastered/complete.
    static func batchMarkMastered(
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
            // Only mark mastered if not already complete
            if state?.isComplete != true {
                markCompleteNoRecompute(student: student, lesson: lesson, context: context)
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
        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            clearStatusNoRecompute(student: student, lesson: lesson, context: context)
        }
        context.safeSave()
    }

    // MARK: - Private Helpers

    private static func toggleScheduledNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lessonIDString = lesson.id.uuidString
        let studentIDString = student.id.uuidString

        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))

        // Check if student is already in an unscheduled lesson
        if let existing = allSLs.first(where: { !$0.isGiven && $0.studentIDs.contains(studentIDString) }) {
            // Remove student from lesson
            var ids = existing.studentIDs
            ids.removeAll { $0 == studentIDString }
            if ids.isEmpty {
                context.delete(existing)
            } else {
                existing.studentIDs = ids
            }
        } else {
            // Add to unscheduled lesson
            if let group = allSLs.first(where: { !$0.isGiven && $0.scheduledFor == nil }) {
                if !group.studentIDs.contains(studentIDString) {
                    group.studentIDs.append(studentIDString)
                }
            } else {
                _ = StudentLessonFactory.insertUnscheduled(
                    lessonID: lesson.id,
                    studentIDs: [student.id],
                    into: context
                )
            }
        }
    }

    private static func togglePresentedNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))

        // Check if student is already in a given lesson
        if let existing = allSLs.first(where: { $0.isGiven && $0.studentIDs.contains(studentIDString) }) {
            // Remove student from lesson
            var ids = existing.studentIDs
            ids.removeAll { $0 == studentIDString }
            if ids.isEmpty {
                context.delete(existing)
            } else {
                existing.studentIDs = ids
            }
            // Remove LessonPresentation
            deleteLessonPresentation(studentID: studentIDString, lessonID: lessonIDString, context: context)
        } else {
            // Add to given lesson
            addStudentToGivenLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
            // Create LessonPresentation
            upsertLessonPresentation(studentID: studentIDString, lessonID: lessonIDString, state: .presented, context: context)
        }
    }

    private static func markCompleteNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        // First, ensure the lesson is marked as presented
        let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonIDString }))
        if allSLs.first(where: { $0.isGiven && $0.studentIDs.contains(studentIDString) }) == nil {
            addStudentToGivenLesson(student: student, studentIDString: studentIDString, lesson: lesson, in: allSLs, context: context)
        }

        // Optionally create/update WorkModel if one exists
        if let work = findOrCreateWork(student: student, lesson: lesson, context: context) {
            work.status = .complete
            work.completedAt = AppCalendar.startOfDay(Date())
        }

        // Create/update LessonPresentation with mastered state
        upsertLessonPresentation(studentID: studentIDString, lessonID: lessonIDString, state: .mastered, context: context)

        // Auto-enroll in track if lesson belongs to a track
        GroupTrackService.autoEnrollInTrackIfNeeded(lesson: lesson, studentIDs: [studentIDString], modelContext: context)

        // Check if track is now complete
        GroupTrackService.checkAndCompleteTrackIfNeeded(lesson: lesson, studentID: studentIDString, modelContext: context)
    }

    private static func clearStatusNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lid = lesson.id
        let sidString = student.id.uuidString
        let lidString = lid.uuidString

        let sls = context.safeFetch(FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lidString }))
        for sl in sls where sl.studentIDs.contains(sidString) {
            var newIDs = sl.studentIDs
            newIDs.removeAll { $0 == sidString }
            if newIDs.isEmpty { context.delete(sl) } else { sl.studentIDs = newIDs }
        }

        // Delete WorkModels for this student/lesson
        let allWorkModels = context.safeFetch(FetchDescriptor<WorkModel>())
        let workModelsToDelete = allWorkModels.filter { work in
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sidString }
            guard hasStudent else { return false }
            guard let slID = work.studentLessonID,
                  let sl = sls.first(where: { $0.id == slID }),
                  UUID(uuidString: sl.lessonID) == lid else { return false }
            return true
        }
        for work in workModelsToDelete {
            context.delete(work)
        }

        // Delete LessonPresentation
        deleteLessonPresentation(studentID: sidString, lessonID: lidString, context: context)
    }

    private static func addStudentToGivenLesson(student: Student, studentIDString: String, lesson: Lesson, in allSLs: [StudentLesson], context: ModelContext) {
        let today = Date()
        if let group = allSLs.first(where: { $0.isGiven && ($0.givenAt ?? Date.distantPast).isSameDay(as: today) }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                GroupTrackService.autoEnrollInTrackIfNeeded(lesson: lesson, studentIDs: [studentIDString], modelContext: context)
            }
        } else {
            _ = StudentLessonFactory.insertPresented(
                lessonID: lesson.id,
                studentIDs: [student.id],
                into: context
            )
            GroupTrackService.autoEnrollInTrackIfNeeded(lesson: lesson, studentIDs: [studentIDString], modelContext: context)
        }
    }

    private static func findOrCreateWork(student: Student, lesson: Lesson, context: ModelContext) -> WorkModel? {
        let sid = student.id
        let lid = lesson.id
        let allWorkModels = context.safeFetch(FetchDescriptor<WorkModel>())

        let existingWork = allWorkModels.first { work in
            let hasStudent = (work.participants ?? []).contains { $0.studentID == sid.uuidString }
            guard hasStudent else { return false }
            guard let slID = work.studentLessonID else { return false }
            let allSLs = context.safeFetch(FetchDescriptor<StudentLesson>())
            guard let sl = allSLs.first(where: { $0.id == slID }),
                  UUID(uuidString: sl.lessonID) == lid else { return false }
            return true
        }

        if let existing = existingWork {
            return existing
        }

        let repository = WorkRepository(context: context)
        return try? repository.createWork(
            studentID: sid,
            lessonID: lid,
            title: nil,
            kind: nil,
            presentationID: nil,
            scheduledDate: nil
        )
    }

    private static func upsertLessonPresentation(studentID: String, lessonID: String, state: LessonPresentationState, context: ModelContext) {
        let allLessonPresentations = context.safeFetch(FetchDescriptor<LessonPresentation>())
        let existing = allLessonPresentations.first { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }

        if let existing = existing {
            if state == .mastered && existing.state != .mastered {
                existing.state = .mastered
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
                masteredAt: state == .mastered ? Date() : nil
            )
            context.insert(lp)
        }
    }

    private static func deleteLessonPresentation(studentID: String, lessonID: String, context: ModelContext) {
        let allLessonPresentations = context.safeFetch(FetchDescriptor<LessonPresentation>())
        let toDelete = allLessonPresentations.filter { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }
        for lp in toDelete {
            context.delete(lp)
        }
    }
}
