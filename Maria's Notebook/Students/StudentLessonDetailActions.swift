import Foundation
import SwiftUI
import Combine
import SwiftData

@MainActor
final class StudentLessonDetailActions: ObservableObject {
    func applyEditsToModel(
        studentLesson: StudentLesson,
        editingLessonID: UUID,
        scheduledFor: Date?,
        givenAt: Date?,
        isPresented: Bool,
        notes: String,
        needsAnotherPresentation: Bool,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [Student],
        lessons: [Lesson],
        calendar: Calendar
    ) {
        // Do not allow zero-student lessons; skip applying edits if empty selection
        guard !selectedStudentIDs.isEmpty else { return }

        // CloudKit compatibility: Convert UUID to String for assignment
        studentLesson.lessonID = editingLessonID.uuidString
        studentLesson.setScheduledFor(scheduledFor, using: calendar)
        studentLesson.givenAt = givenAt.map { calendar.startOfDay(for: $0) }
        studentLesson.isPresented = isPresented
        studentLesson.notes = notes
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.studentIDs = selectedStudentIDs.map { $0.uuidString }
        studentLesson.students = studentsAll.filter { selectedStudentIDs.contains($0.id) }
        studentLesson.lesson = lessons.first(where: { $0.id == editingLessonID })
    }

    func autoCreateNextIfNeeded(
        wasGiven: Bool,
        nowGiven: Bool,
        nextLesson: Lesson?,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [Student],
        lessons: [Lesson],
        studentLessonsAll: [StudentLesson],
        context: ModelContext
    ) {
        guard !wasGiven, nowGiven, let next = nextLesson else { return }

        let result = PlanNextLessonService.planLesson(
            next,
            forStudents: selectedStudentIDs,
            allStudents: studentsAll,
            allLessons: lessons,
            existingStudentLessons: studentLessonsAll,
            context: context
        )

        if case .success = result {
            StudentLessonDetailUtilities.notifyInboxRefresh()
        }
    }

    func planNextLessonInGroup(
        next: Lesson,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [Student],
        lessons: [Lesson],
        studentLessonsAll: [StudentLesson],
        context: ModelContext
    ) -> Bool {
        let result = PlanNextLessonService.planLesson(
            next,
            forStudents: selectedStudentIDs,
            allStudents: studentsAll,
            allLessons: lessons,
            existingStudentLessons: studentLessonsAll,
            context: context
        )

        if case .success = result {
            context.safeSave()
            StudentLessonDetailUtilities.notifyInboxRefresh()
            return true
        }
        return false
    }

    func moveStudentsToInbox(
        currentLesson: Lesson,
        studentsToMove: Set<UUID>,
        studentsAll: [Student],
        studentLessonsAll: [StudentLesson],
        context: ModelContext
    ) -> [String] {
        guard !studentsToMove.isEmpty else { return [] }

        let movedStudentNames = studentsAll
            .filter { studentsToMove.contains($0.id) }
            .map { StudentFormatter.displayName(for: $0) }

        let targetSet = studentsToMove
        let existing = studentLessonsAll.first(where: { sl in
            sl.resolvedLessonID == currentLesson.id && sl.scheduledFor == nil && !sl.isGiven && Set(sl.resolvedStudentIDs) == targetSet
        })

        if let ex = existing {
            ex.students = studentsAll.filter { targetSet.contains($0.id) }
            ex.lesson = currentLesson
        } else {
            let newStudentLesson = StudentLessonFactory.makeUnscheduled(
                lessonID: currentLesson.id,
                studentIDs: Array(targetSet)
            )
            StudentLessonFactory.attachRelationships(
                to: newStudentLesson,
                lesson: currentLesson,
                students: studentsAll.filter { targetSet.contains($0.id) }
            )
            context.insert(newStudentLesson)
        }

        context.safeSave()
        StudentLessonDetailUtilities.notifyInboxRefresh()
        return movedStudentNames
    }

    func toggleWorkCompletion(_ work: WorkModel, studentID: UUID, context: ModelContext) {
        if work.isStudentCompleted(studentID) {
            work.markStudent(studentID, completedAt: nil)
        } else {
            work.markStudent(studentID, completedAt: Date())
        }
        context.safeSave()
    }

    func nextLessonInGroup(from current: Lesson?, lessons: [Lesson]) -> Lesson? {
        guard let current else { return nil }
        return PlanNextLessonService.findNextLesson(after: current, in: lessons)
    }
}

