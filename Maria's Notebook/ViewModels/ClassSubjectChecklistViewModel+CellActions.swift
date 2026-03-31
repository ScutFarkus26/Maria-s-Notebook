// ClassSubjectChecklistViewModel+CellActions.swift
// Individual cell toggle/mark/clear operations for ClassSubjectChecklistViewModel.

import Foundation
import SwiftData

extension ClassSubjectChecklistViewModel {

    // MARK: - Individual Cell Actions

    func toggleScheduled(student: Student, lesson: Lesson, context: ModelContext) {
        toggleScheduledNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    func toggleScheduledNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lessonIDString = lesson.id.uuidString
        let studentIDString = student.id.uuidString

        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.lessonID == lessonIDString }
        )
        let allLAs = context.safeFetch(descriptor)

        if let existing = findUnscheduledLessonContaining(student: studentIDString, in: allLAs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
        } else {
            addStudentToUnscheduledLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
        }
    }

    func findUnscheduledLessonContaining(student: String, in lessons: [LessonAssignment]) -> LessonAssignment? {
        lessons.first(where: { !$0.isPresented && $0.studentIDs.contains(student) })
    }

    func removeStudentFromLesson(student: String, lesson: LessonAssignment, context: ModelContext) {
        var ids = lesson.studentIDs
        ids.removeAll { $0 == student }
        if ids.isEmpty {
            context.delete(lesson)
        } else {
            lesson.studentIDs = ids
        }
    }

    func addStudentToUnscheduledLesson(
        student: Student, studentIDString: String, lesson: Lesson,
        in allLAs: [LessonAssignment], context: ModelContext
    ) {
        if let group = allLAs.first(where: { !$0.isPresented && $0.scheduledFor == nil }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
            }
        } else {
            PresentationFactory.insertDraft(
                lessonID: lesson.id,
                studentIDs: [student.id],
                context: context
            )
        }
    }

    func markComplete(student: Student, lesson: Lesson, context: ModelContext) {
        markCompleteNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    func markCompleteNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.lessonID == lessonIDString }
        )
        let allLAs = context.safeFetch(descriptor)
        if findGivenLessonContaining(student: studentIDString, in: allLAs) == nil {
            addStudentToGivenLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
        }

        findOrCreateWorkAndMarkComplete(student: student, lesson: lesson, context: context)

        upsertLessonPresentation(
            studentID: studentIDString, lessonID: lessonIDString,
            state: .proficient, context: context
        )
        GroupTrackService.autoEnrollInTrackIfNeeded(
            lesson: lesson, studentIDs: [studentIDString], modelContext: context
        )
        GroupTrackService.checkAndCompleteTrackIfNeeded(
            lesson: lesson, studentID: studentIDString, modelContext: context
        )
    }

    func togglePresented(student: Student, lesson: Lesson, context: ModelContext) {
        togglePresentedNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    func togglePresentedNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.lessonID == lessonIDString }
        )
        let allLAs = context.safeFetch(descriptor)

        if let existing = findGivenLessonContaining(student: studentIDString, in: allLAs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
            deleteLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString, context: context
            )
        } else {
            addStudentToGivenLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
            upsertLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString,
                state: .presented, context: context
            )
        }
    }

    func findGivenLessonContaining(student: String, in lessons: [LessonAssignment]) -> LessonAssignment? {
        lessons.first(where: { $0.isPresented && $0.studentIDs.contains(student) })
    }

    func addStudentToGivenLesson(
        student: Student, studentIDString: String, lesson: Lesson,
        in allLAs: [LessonAssignment], context: ModelContext
    ) {
        let today = Date()
        let isGivenToday = { (la: LessonAssignment) -> Bool in
            la.isPresented && (la.presentedAt ?? Date.distantPast).isSameDay(as: today)
        }
        if let group = allLAs.first(where: isGivenToday) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lesson: lesson, studentIDs: [studentIDString], modelContext: context
                )
            }
        } else {
            PresentationFactory.insertPresented(
                lessonID: lesson.id,
                studentIDs: [student.id],
                context: context
            )
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: lesson, studentIDs: [studentIDString], modelContext: context
            )
        }
    }

    // MARK: - Previously Presented (Undated)

    func togglePreviouslyPresented(student: Student, lesson: Lesson, context: ModelContext) {
        togglePreviouslyPresentedNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    func togglePreviouslyPresentedNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString

        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.lessonID == lessonIDString }
        )
        let allLAs = context.safeFetch(descriptor)

        if let existing = findGivenLessonContaining(student: studentIDString, in: allLAs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
            deleteLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString, context: context
            )
        } else {
            addStudentToUndatedLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
            upsertLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString,
                state: .presented, context: context
            )
        }
    }

    func addStudentToUndatedLesson(
        student: Student, studentIDString: String, lesson: Lesson,
        in allLAs: [LessonAssignment], context: ModelContext
    ) {
        let isUndatedPresented = { (la: LessonAssignment) -> Bool in
            la.isPresented && la.presentedAt == nil
        }
        if let group = allLAs.first(where: isUndatedPresented) {
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

    func clearStatus(student: Student, lesson: Lesson, context: ModelContext) {
        clearStatusNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    func clearStatusNoRecompute(student: Student, lesson: Lesson, context: ModelContext) {
        let lid = lesson.id
        let sidString = student.id.uuidString
        let lidString = lid.uuidString

        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.lessonID == lidString }
        )
        let las = context.safeFetch(descriptor)
        for la in las where la.studentIDs.contains(sidString) {
            var newIDs = la.studentIDs
            newIDs.removeAll { $0 == sidString }
            if newIDs.isEmpty {
                context.delete(la)
            } else {
                la.studentIDs = newIDs
            }
        }

        // PERF: Filter by lessonID in predicate to avoid loading all non-complete work.
        let workDescriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { $0.statusRaw != "complete" && $0.lessonID == lidString }
        )
        let workModelsToDelete = context.safeFetch(workDescriptor).filter { work in
            (work.participants ?? []).contains { $0.studentID == sidString }
        }
        for work in workModelsToDelete {
            context.delete(work)
        }

        deleteLessonPresentation(studentID: sidString, lessonID: lidString, context: context)
    }
}
