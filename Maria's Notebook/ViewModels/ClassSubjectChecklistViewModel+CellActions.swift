// ClassSubjectChecklistViewModel+CellActions.swift
// Individual cell toggle/mark/clear operations for ClassSubjectChecklistViewModel.

import Foundation
import CoreData

extension ClassSubjectChecklistViewModel {

    // MARK: - Individual Cell Actions

    func toggleScheduled(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        toggleScheduledNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    func toggleScheduledNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let lessonUUID = lesson.id, let studentUUID = student.id else { return }
        let lessonIDString = lessonUUID.uuidString
        let studentIDString = studentUUID.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        let allLAs = context.safeFetch(request)

        if let existing = findUnscheduledLessonContaining(student: studentIDString, in: allLAs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
        } else {
            addStudentToUnscheduledLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
        }
    }

    func findUnscheduledLessonContaining(student: String, in lessons: [CDLessonAssignment]) -> CDLessonAssignment? {
        lessons.first(where: { !$0.isPresented && $0.studentIDs.contains(student) })
    }

    func removeStudentFromLesson(student: String, lesson: CDLessonAssignment, context: NSManagedObjectContext) {
        var ids = lesson.studentIDs
        ids.removeAll { $0 == student }
        if ids.isEmpty {
            context.delete(lesson)
        } else {
            lesson.studentIDs = ids
        }
    }

    func addStudentToUnscheduledLesson(
        student: CDStudent, studentIDString: String, lesson: CDLesson,
        in allLAs: [CDLessonAssignment], context: NSManagedObjectContext
    ) {
        if let group = allLAs.first(where: { !$0.isPresented && $0.scheduledFor == nil }) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
            }
        } else {
            guard let lessonID = lesson.id, let studentID = student.id else { return }
            _ = PresentationFactory.makeDraft(
                lessonID: lessonID,
                studentIDs: [studentID],
                context: context
            )
        }
    }

    func markComplete(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        markCompleteNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    func markCompleteNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let studentUUID = student.id, let lessonUUID = lesson.id else { return }
        let studentIDString = studentUUID.uuidString
        let lessonIDString = lessonUUID.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        let allLAs = context.safeFetch(request)
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
            lessonSubject: lesson.subject, lessonGroup: lesson.group, studentIDs: [studentIDString], context: context
        )
        GroupTrackService.checkAndCompleteTrackIfNeeded(
            lessonSubject: lesson.subject, lessonGroup: lesson.group, studentID: studentIDString, context: context
        )
    }

    func togglePresented(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        togglePresentedNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    func togglePresentedNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let studentUUID = student.id, let lessonUUID = lesson.id else { return }
        let studentIDString = studentUUID.uuidString
        let lessonIDString = lessonUUID.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        let allLAs = context.safeFetch(request)

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

    func findGivenLessonContaining(student: String, in lessons: [CDLessonAssignment]) -> CDLessonAssignment? {
        lessons.first(where: { $0.isPresented && $0.studentIDs.contains(student) })
    }

    func addStudentToGivenLesson(
        student: CDStudent, studentIDString: String, lesson: CDLesson,
        in allLAs: [CDLessonAssignment], context: NSManagedObjectContext
    ) {
        let today = Date()
        let isGivenToday = { (la: CDLessonAssignment) -> Bool in
            la.isPresented && (la.presentedAt ?? Date.distantPast).isSameDay(as: today)
        }
        if let group = allLAs.first(where: isGivenToday) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lessonSubject: lesson.subject, lessonGroup: lesson.group, studentIDs: [studentIDString], context: context
                )
            }
        } else {
            guard let lessonUUID = lesson.id, let studentUUID = student.id else { return }
            _ = PresentationFactory.makePresented(
                lessonID: lessonUUID,
                studentIDs: [studentUUID],
                context: context
            )
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lessonSubject: lesson.subject, lessonGroup: lesson.group, studentIDs: [studentIDString], context: context
            )
        }
    }

    // MARK: - Previously Presented (Undated)

    func togglePreviouslyPresented(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        togglePreviouslyPresentedNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    func togglePreviouslyPresentedNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let studentUUID = student.id, let lessonUUID = lesson.id else { return }
        let studentIDString = studentUUID.uuidString
        let lessonIDString = lessonUUID.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        let allLAs = context.safeFetch(request)

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
        student: CDStudent, studentIDString: String, lesson: CDLesson,
        in allLAs: [CDLessonAssignment], context: NSManagedObjectContext
    ) {
        let isUndatedPresented = { (la: CDLessonAssignment) -> Bool in
            la.isPresented && la.presentedAt == nil
        }
        if let group = allLAs.first(where: isUndatedPresented) {
            if !group.studentIDs.contains(studentIDString) {
                group.studentIDs.append(studentIDString)
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lessonSubject: lesson.subject, lessonGroup: lesson.group, studentIDs: [studentIDString], context: context
                )
            }
        } else {
            guard let lessonUUID = lesson.id, let studentUUID = student.id else { return }
            _ = PresentationFactory.makePreviouslyPresented(
                lessonID: lessonUUID,
                studentIDs: [studentUUID],
                context: context
            )
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lessonSubject: lesson.subject, lessonGroup: lesson.group, studentIDs: [studentIDString], context: context
            )
        }
    }

    func clearStatus(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        clearStatusNoRecompute(student: student, lesson: lesson, context: context)
        context.safeSave()
        recomputeMatrix(context: context)
    }

    func clearStatusNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let lid = lesson.id, let sid = student.id else { return }
        let sidString = sid.uuidString
        let lidString = lid.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lidString)
        let las = context.safeFetch(request)
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
        let workRequest = CDFetchRequest(CDWorkModel.self)
        workRequest.predicate = NSPredicate(format: "statusRaw != %@ AND lessonID == %@", "complete", lidString)
        let workModelsToDelete = context.safeFetch(workRequest).filter { work in
            ((work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []).contains { $0.studentID == sidString }
        }
        for work in workModelsToDelete {
            context.delete(work)
        }

        deleteLessonPresentation(studentID: sidString, lessonID: lidString, context: context)
    }
}
