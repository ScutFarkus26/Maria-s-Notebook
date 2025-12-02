import Foundation
import SwiftData
import Combine

@MainActor
final class StudentDetailViewModel: ObservableObject {
    let student: Student

    // Published caches and summaries
    @Published private(set) var lessonsByID: [UUID: Lesson] = [:]
    @Published private(set) var studentLessonsByID: [UUID: StudentLesson] = [:]
    @Published private(set) var worksForStudent: [WorkModel] = []
    @Published private(set) var nextLessonsForStudent: [StudentLessonSnapshot] = []
    @Published private(set) var workSummary: WorkSummary = .empty
    @Published private(set) var masteredLessonIDs: Set<UUID> = []
    @Published private(set) var plannedLessonIDs: Set<UUID> = []

    init(student: Student) {
        self.student = student
    }

    func updateData(lessons: [Lesson], studentLessons: [StudentLesson], workModels: [WorkModel]) {
        // Build caches
        lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        studentLessonsByID = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })

        // Works for this student
        worksForStudent = workModels
            .filter { $0.studentIDs.contains(student.id) }
            .sorted { $0.createdAt > $1.createdAt }

        // Next lessons for this student (not yet presented)
        let fetchedSL = studentLessons.filter { $0.studentIDs.contains(student.id) && !$0.isPresented }
        let sortedSL = fetchedSL.sorted { lhs, rhs in
            switch (lhs.scheduledFor, rhs.scheduledFor) {
            case let (l?, r?):
                return l < r
            case (nil, nil):
                return lhs.createdAt < rhs.createdAt
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
        nextLessonsForStudent = sortedSL.map { $0.snapshot() }

        // Summaries
        workSummary = Self.computeWorkSummary(for: student.id, works: worksForStudent, studentLessonsByID: studentLessonsByID)
        masteredLessonIDs = Set(studentLessons.filter { $0.isPresented && $0.studentIDs.contains(student.id) }.map { $0.lessonID })
        plannedLessonIDs = Set(nextLessonsForStudent.map { $0.lessonID })
    }

    private static func computeWorkSummary(for studentID: UUID, works: [WorkModel], studentLessonsByID: [UUID: StudentLesson]) -> WorkSummary {
        var practice = Set<UUID>()
        var follow = Set<UUID>()
        var pendingPractice = Set<UUID>()
        var pendingFollow = Set<UUID>()
        var pendingAny = Set<UUID>()

        for work in works {
            guard let slID = work.studentLessonID, let sl = studentLessonsByID[slID] else { continue }
            let lessonID = sl.lessonID
            switch work.workType {
            case .practice:
                practice.insert(lessonID)
                if !work.isStudentCompleted(studentID) {
                    pendingPractice.insert(lessonID)
                    pendingAny.insert(lessonID)
                }
            case .followUp:
                follow.insert(lessonID)
                if !work.isStudentCompleted(studentID) {
                    pendingFollow.insert(lessonID)
                    pendingAny.insert(lessonID)
                }
            case .research:
                continue
            }
        }

        return WorkSummary(
            practiceLessonIDs: practice,
            followUpLessonIDs: follow,
            pendingPracticeLessonIDs: pendingPractice,
            pendingFollowUpLessonIDs: pendingFollow,
            pendingWorkLessonIDs: pendingAny
        )
    }

    struct WorkSummary {
        let practiceLessonIDs: Set<UUID>
        let followUpLessonIDs: Set<UUID>
        let pendingPracticeLessonIDs: Set<UUID>
        let pendingFollowUpLessonIDs: Set<UUID>
        let pendingWorkLessonIDs: Set<UUID>

        static let empty = WorkSummary(
            practiceLessonIDs: [],
            followUpLessonIDs: [],
            pendingPracticeLessonIDs: [],
            pendingFollowUpLessonIDs: [],
            pendingWorkLessonIDs: []
        )
    }
}
