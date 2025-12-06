import Foundation
import SwiftData

enum PlanningActions {
    static func moveToInbox(_ sl: StudentLesson, context: ModelContext) {
        sl.scheduledFor = nil
        Task { @MainActor in try? context.save() }
    }

    static func planNextLesson(for sl: StudentLesson, lessons: [Lesson], students: [Student], studentLessons: [StudentLesson], context: ModelContext) {
        guard let currentLesson = lessons.first(where: { $0.id == sl.lessonID }) else { return }
        let currentSubject = currentLesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = currentLesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return }

        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }

        guard let idx = candidates.firstIndex(where: { $0.id == currentLesson.id }), idx + 1 < candidates.count else { return }
        let next = candidates[idx + 1]

        let sameStudents = Set(sl.resolvedStudentIDs)
        let exists = studentLessons.contains { existing in
            existing.resolvedLessonID == next.id && Set(existing.resolvedStudentIDs) == sameStudents && existing.givenAt == nil
        }
        guard !exists else { return }

        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: next.id,
            studentIDs: sl.studentIDs,
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newStudentLesson.students = students.filter { sameStudents.contains($0.id) }
        newStudentLesson.lesson = lessons.first(where: { $0.id == next.id })
        newStudentLesson.syncSnapshotsFromRelationships()
        context.insert(newStudentLesson)
        try? context.save()
    }
}
