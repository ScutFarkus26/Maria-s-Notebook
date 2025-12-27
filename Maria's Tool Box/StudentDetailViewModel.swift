// StudentDetailViewModel.swift
// View model for StudentDetailView. Manages caches, selections, and derived summaries.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import SwiftData
import Combine
import SwiftUI

/// View model backing StudentDetailView.
/// Builds in-memory caches and exposes selection state for sheets.
/// All methods maintain existing behavior; this refactor adds structure and docs only.
@MainActor
final class StudentDetailViewModel: ObservableObject {
    // MARK: - Properties
    let student: Student

    // MARK: - Published Caches
    // Published caches and summaries
    @Published private(set) var lessonsByID: [UUID: Lesson] = [:]
    @Published private(set) var studentLessonsByID: [UUID: StudentLesson] = [:]
    @Published private(set) var nextLessonsForStudent: [StudentLessonSnapshot] = []
    @Published private(set) var masteredLessonIDs: Set<UUID> = []
    @Published private(set) var plannedLessonIDs: Set<UUID> = []

    @Published private(set) var contractsForStudent: [WorkContract] = []
    @Published private(set) var contractSummary: ContractSummary = .empty

    @Published private(set) var worksForStudent: [WorkModel] = []

    // MARK: - UI State
    // UI selection and toast state moved from the view
    @Published var selectedLessonForGive: Lesson? = nil
    @Published var giveStartGiven: Bool = false
    @Published var selectedWorkForDetail: WorkModel? = nil
    @Published var selectedStudentLessonForDetail: StudentLesson? = nil
    @Published var toastMessage: String? = nil

    // MARK: - Initialization
    init(student: Student) {
        self.student = student
    }

    // MARK: - Public API
    func updateData(lessons: [Lesson], studentLessons: [StudentLesson], workModels: [WorkModel]) {
        // Build caches
        lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        studentLessonsByID = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })

        // Next lessons for this student (not yet presented)
        let fetchedSL = studentLessons.filter { $0.resolvedStudentIDs.contains(student.id) && !$0.isPresented }
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
        masteredLessonIDs = Set(studentLessons.filter { $0.isPresented && $0.resolvedStudentIDs.contains(student.id) }.map { $0.resolvedLessonID })
        plannedLessonIDs = Set(nextLessonsForStudent.map { $0.lessonID })

        // worksForStudent intentionally left empty as per instructions
        worksForStudent = []
    }

    func updateContracts(_ contracts: [WorkContract]) {
        // Set and compute summary
        self.contractsForStudent = contracts
        self.contractSummary = Self.computeContractSummary(contracts: contracts)
    }

    private static func computeContractSummary(contracts: [WorkContract]) -> ContractSummary {
        var practice = Set<UUID>()
        var follow = Set<UUID>()
        var pending = Set<UUID>()

        for c in contracts where c.status != .complete {
            guard let lid = UUID(uuidString: c.lessonID) else { continue }
            if let k = c.kind {
                switch k {
                case .practiceLesson: practice.insert(lid)
                case .followUpAssignment: follow.insert(lid)
                case .research: break
                }
            }
            // Loose pending: no scheduledDate means pending
            if c.scheduledDate == nil { pending.insert(lid) }
        }
        return ContractSummary(practiceLessonIDs: practice, followUpLessonIDs: follow, pendingLessonIDs: pending)
    }

    // MARK: - Types
    struct ContractSummary {
        let practiceLessonIDs: Set<UUID>
        let followUpLessonIDs: Set<UUID>
        let pendingLessonIDs: Set<UUID>

        static let empty = ContractSummary(
            practiceLessonIDs: [],
            followUpLessonIDs: [],
            pendingLessonIDs: []
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
        let matches = studentLessonsByID.values.filter { $0.resolvedLessonID == lessonID && $0.resolvedStudentIDs.contains(studentID) }
        return matches.sorted { lhs, rhs in
            let lDate = lhs.givenAt ?? lhs.scheduledFor ?? lhs.createdAt
            let rDate = rhs.givenAt ?? rhs.scheduledFor ?? rhs.createdAt
            return lDate > rDate
        }.first
    }

    func upcomingStudentLesson(for lessonID: UUID, studentID: UUID) -> StudentLesson? {
        let matches = studentLessonsByID.values.filter { $0.resolvedLessonID == lessonID && $0.resolvedStudentIDs.contains(studentID) && !$0.isGiven }
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
            return sl.resolvedLessonID == lesson.id
        }) {
            selectedWorkForDetail = existing
            return
        }
        let sl = latestStudentLesson(for: lesson.id, studentID: student.id) ?? ensureStudentLesson(for: lesson, modelContext: modelContext)
        let work = WorkModel(
            id: UUID(),
            title: "\(type.rawValue): \(lesson.name)",
            workType: type,
            studentLessonID: sl.id,
            notes: "",
            createdAt: Date()
        )
        work.participants = [WorkParticipantEntity(studentID: student.id, completedAt: nil, work: work)]
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
            return sl.resolvedLessonID == lesson.id
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
                workType: type,
                studentLessonID: sl.id,
                notes: "",
                createdAt: Date()
            )
            work.participants = [WorkParticipantEntity(studentID: sid, completedAt: nil, work: work)]
            modelContext.insert(work)
            try? modelContext.save()
            showToast("\(type.rawValue) work created")
        }
    }
}

