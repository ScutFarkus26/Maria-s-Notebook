import Foundation
import SwiftData
import Combine
import SwiftUI

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

    // UI selection and toast state moved from the view
    @Published var selectedLessonForGive: Lesson? = nil
    @Published var giveStartGiven: Bool = false
    @Published var selectedWorkForDetail: WorkModel? = nil
    @Published var selectedStudentLessonForDetail: StudentLesson? = nil
    @Published var toastMessage: String? = nil

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

    // MARK: - UI Actions moved from View
    func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut) { self.toastMessage = nil }
        }
    }

    func latestStudentLesson(for lessonID: UUID, studentID: UUID) -> StudentLesson? {
        let matches = studentLessonsByID.values.filter { $0.lessonID == lessonID && $0.studentIDs.contains(studentID) }
        return matches.sorted { lhs, rhs in
            let lDate = lhs.givenAt ?? lhs.scheduledFor ?? lhs.createdAt
            let rDate = rhs.givenAt ?? rhs.scheduledFor ?? rhs.createdAt
            return lDate > rDate
        }.first
    }

    func upcomingStudentLesson(for lessonID: UUID, studentID: UUID) -> StudentLesson? {
        let matches = studentLessonsByID.values.filter { $0.lessonID == lessonID && $0.studentIDs.contains(studentID) && !$0.isGiven }
        return matches.sorted { lhs, rhs in
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
        }.first
    }

    func ensureStudentLesson(for lesson: Lesson, modelContext: ModelContext) -> StudentLesson {
        if let existing = latestStudentLesson(for: lesson.id, studentID: student.id) {
            return existing
        }
        let created = StudentLesson(
            lessonID: lesson.id,
            studentIDs: [student.id],
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    func openPlan(for lesson: Lesson, modelContext: ModelContext) {
        if let sl = upcomingStudentLesson(for: lesson.id, studentID: student.id) {
            selectedStudentLessonForDetail = sl
        } else {
            selectedLessonForGive = lesson
            giveStartGiven = false
        }
    }

    func openMastered(for lesson: Lesson, modelContext: ModelContext) {
        let presented = studentLessonsByID.values
            .filter { $0.lessonID == lesson.id && $0.studentIDs.contains(student.id) && $0.isPresented }
            .sorted(by: { ($0.givenAt ?? $0.createdAt) > ($1.givenAt ?? $1.createdAt) })
        if let sl = presented.first {
            selectedStudentLessonForDetail = sl
        } else {
            selectedLessonForGive = lesson
            giveStartGiven = true
        }
    }

    func openWork(for lesson: Lesson, type: WorkModel.WorkType, modelContext: ModelContext) {
        if let existing = worksForStudent.first(where: { work in
            guard work.workType == type, let slID = work.studentLessonID, let sl = studentLessonsByID[slID] else { return false }
            return sl.lessonID == lesson.id
        }) {
            selectedWorkForDetail = existing
            return
        }
        let sl = latestStudentLesson(for: lesson.id, studentID: student.id) ?? ensureStudentLesson(for: lesson, modelContext: modelContext)
        let work = WorkModel(
            id: UUID(),
            title: "\(type.rawValue): \(lesson.name)",
            studentIDs: [student.id],
            workType: type,
            studentLessonID: sl.id,
            notes: "",
            createdAt: Date()
        )
        work.ensureParticipantsFromStudentIDs()
        modelContext.insert(work)
        try? modelContext.save()
        selectedWorkForDetail = work
        showToast("\(type.rawValue) work created")
    }

    func togglePresented(for lesson: Lesson, modelContext: ModelContext) {
        if masteredLessonIDs.contains(lesson.id) {
            openMastered(for: lesson, modelContext: modelContext)
            return
        }
        if let upcoming = upcomingStudentLesson(for: lesson.id, studentID: student.id) {
            upcoming.isPresented = true
            try? modelContext.save()
        } else {
            let sl = StudentLesson(
                lessonID: lesson.id,
                studentIDs: [student.id],
                createdAt: Date(),
                scheduledFor: nil,
                givenAt: nil,
                isPresented: true,
                notes: "",
                needsPractice: false,
                needsAnotherPresentation: false,
                followUpWork: ""
            )
            modelContext.insert(sl)
            try? modelContext.save()
            showToast("Presentation recorded")
        }
    }

    func toggleWork(for lesson: Lesson, type: WorkModel.WorkType, modelContext: ModelContext) {
        let sid = student.id
        if let existing = worksForStudent.first(where: { work in
            guard work.workType == type, let slID = work.studentLessonID, let sl = studentLessonsByID[slID] else { return false }
            return sl.lessonID == lesson.id
        }) {
            if existing.isStudentCompleted(sid) {
                existing.markStudent(sid, completedAt: nil)
            } else {
                existing.markStudent(sid, completedAt: Date())
            }
            try? modelContext.save()
        } else {
            let sl = ensureStudentLesson(for: lesson, modelContext: modelContext)
            let work = WorkModel(
                id: UUID(),
                title: "\(type.rawValue): \(lesson.name)",
                studentIDs: [sid],
                workType: type,
                studentLessonID: sl.id,
                notes: "",
                createdAt: Date()
            )
            work.ensureParticipantsFromStudentIDs()
            modelContext.insert(work)
            try? modelContext.save()
            showToast("\(type.rawValue) work created")
        }
    }
}
