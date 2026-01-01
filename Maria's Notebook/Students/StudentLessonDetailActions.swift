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

        studentLesson.lessonID = editingLessonID
        studentLesson.setScheduledFor(scheduledFor, using: calendar)
        print("[Detail] tz=\(calendar.timeZone.identifier) set scheduledFor=\(String(describing: scheduledFor)) for sl=\(studentLesson.id)")
        studentLesson.givenAt = givenAt.map { calendar.startOfDay(for: $0) }
        studentLesson.isPresented = isPresented
        studentLesson.notes = notes
        studentLesson.needsAnotherPresentation = needsAnotherPresentation
        studentLesson.studentIDs = Array(selectedStudentIDs)
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
        let sameStudents = Set(selectedStudentIDs)
        // Do not create next lesson entries for zero students
        guard !sameStudents.isEmpty else { return }
        let exists = studentLessonsAll.contains { sl in
            sl.resolvedLessonID == next.id && Set(sl.resolvedStudentIDs) == sameStudents && sl.givenAt == nil
        }
        guard !exists else { return }
        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: next.id,
            studentIDs: Array(sameStudents),
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newStudentLesson.students = studentsAll.filter { sameStudents.contains($0.id) }
        newStudentLesson.lesson = lessons.first(where: { $0.id == next.id })
        context.insert(newStudentLesson)
        StudentLessonDetailUtilities.notifyInboxRefresh()
    }

    func planNextLessonInGroup(
        next: Lesson,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [Student],
        lessons: [Lesson],
        studentLessonsAll: [StudentLesson],
        context: ModelContext
    ) -> Bool {
        let sameStudents = Set(selectedStudentIDs)
        // Do not plan next lesson entries for zero students
        guard !sameStudents.isEmpty else { return false }
        let exists = studentLessonsAll.contains { sl in
            sl.resolvedLessonID == next.id && Set(sl.resolvedStudentIDs) == sameStudents && sl.givenAt == nil
        }
        if !exists {
            let newStudentLesson = StudentLesson(
                id: UUID(),
                lessonID: next.id,
                studentIDs: Array(selectedStudentIDs),
                createdAt: Date(),
                scheduledFor: nil,
                givenAt: nil,
                notes: "",
                needsPractice: false,
                needsAnotherPresentation: false,
                followUpWork: ""
            )
            newStudentLesson.students = studentsAll.filter { sameStudents.contains($0.id) }
            newStudentLesson.lesson = lessons.first(where: { $0.id == next.id })
            context.insert(newStudentLesson)
            try? context.save()
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
            let newStudentLesson = StudentLesson(
                id: UUID(),
                lessonID: currentLesson.id,
                studentIDs: Array(targetSet),
                createdAt: Date(),
                scheduledFor: nil,
                givenAt: nil,
                notes: "",
                needsPractice: false,
                needsAnotherPresentation: false,
                followUpWork: ""
            )
            newStudentLesson.students = studentsAll.filter { targetSet.contains($0.id) }
            newStudentLesson.lesson = currentLesson
            context.insert(newStudentLesson)
        }

        try? context.save()
        StudentLessonDetailUtilities.notifyInboxRefresh()
        return movedStudentNames
    }

    func toggleWorkCompletion(_ work: WorkModel, studentID: UUID, context: ModelContext) {
        if work.isStudentCompleted(studentID) {
            work.markStudent(studentID, completedAt: nil)
        } else {
            work.markStudent(studentID, completedAt: Date())
        }
        try? context.save()
    }

    func nextLessonInGroup(from current: Lesson?, lessons: [Lesson]) -> Lesson? {
        guard let current else { return nil }
        let currentSubject = current.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = current.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return nil }
        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }
        guard let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count else { return nil }
        return candidates[idx + 1]
    }
}

