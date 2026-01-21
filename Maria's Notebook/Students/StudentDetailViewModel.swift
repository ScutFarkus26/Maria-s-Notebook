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
    @Published private(set) var lessons: [Lesson] = []
    @Published private(set) var studentLessons: [StudentLesson] = []
    @Published private(set) var lessonsByID: [UUID: Lesson] = [:]
    @Published private(set) var studentLessonsByID: [UUID: StudentLesson] = [:]
    @Published private(set) var nextLessonsForStudent: [StudentLessonSnapshot] = []
    /// Lessons that have been presented to this student (based on StudentLesson.isPresented)
    @Published private(set) var presentedLessonIDs: Set<UUID> = []
    /// Lessons that this student has mastered (based on LessonPresentation.state == .mastered)
    @Published private(set) var masteredLessonIDs: Set<UUID> = []
    @Published private(set) var plannedLessonIDs: Set<UUID> = []

    @Published private(set) var workModelsForStudent: [WorkModel] = []
    @Published private(set) var workSummary: WorkSummary = .empty

    // MARK: - UI State
    // UI selection and toast state moved from the view
    @Published var selectedLessonForGive: Lesson? = nil
    @Published var giveStartGiven: Bool = false
    @Published var selectedStudentLessonForDetail: StudentLesson? = nil
    @Published var toastMessage: String? = nil

    // MARK: - Initialization
    init(student: Student) {
        self.student = student
    }

    // MARK: - Data Loading
    /// Load lessons and student lessons from the database using FetchDescriptor.
    /// OPTIMIZATION: Only loads studentLessons for this student and lessons referenced by them.
    func loadData(modelContext: ModelContext) {
        // OPTIMIZATION: Load all studentLessons first, then filter by student
        // Note: SwiftData predicates don't easily support array contains for resolvedStudentIDs,
        // so we fetch all and filter in memory (still better than @Query reactive loading)
        let studentLessonsDescriptor = FetchDescriptor<StudentLesson>(
            sortBy: [
                SortDescriptor(\StudentLesson.scheduledFor, order: .forward),
                SortDescriptor(\StudentLesson.createdAt, order: .forward)
            ]
        )
        let allStudentLessons = (try? modelContext.fetch(studentLessonsDescriptor)) ?? []
        let filteredStudentLessons = allStudentLessons.filter { $0.resolvedStudentIDs.contains(student.id) }

        // OPTIMIZATION: Only fetch lessons that are referenced by this student's studentLessons
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        let neededLessonIDs = Set(filteredStudentLessons.map { $0.resolvedLessonID })
        let fetchedLessons: [Lesson]
        if !neededLessonIDs.isEmpty {
            let allLessons = modelContext.safeFetch(FetchDescriptor<Lesson>())
            fetchedLessons = allLessons.filter { neededLessonIDs.contains($0.id) }
        } else {
            fetchedLessons = []
        }

        // Update published properties
        self.lessons = fetchedLessons
        self.studentLessons = filteredStudentLessons

        // Update derived caches
        updateData(lessons: fetchedLessons, studentLessons: filteredStudentLessons)

        // Load mastered lesson IDs from LessonPresentation records
        loadMasteredLessonIDs(modelContext: modelContext)
    }

    /// Loads lesson IDs that have been mastered by this student from LessonPresentation records.
    private func loadMasteredLessonIDs(modelContext: ModelContext) {
        let studentIDString = student.id.uuidString
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        // Note: Must use stateRaw (stored property) not state (computed property) in predicates
        let masteredStateRaw = LessonPresentationState.mastered.rawValue
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate { lp in
                lp.studentID == studentIDString && lp.stateRaw == masteredStateRaw
            }
        )
        let masteredPresentations = (try? modelContext.fetch(descriptor)) ?? []

        masteredLessonIDs = Set(
            masteredPresentations.compactMap { UUID(uuidString: $0.lessonID) }
        )
    }

    // MARK: - Public API
    func updateData(lessons: [Lesson], studentLessons: [StudentLesson]) {
        // Build caches
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        lessonsByID = Dictionary(lessons.uniqueByID.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        studentLessonsByID = Dictionary(studentLessons.uniqueByID.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

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
        presentedLessonIDs = Set(studentLessons.filter { $0.isPresented && $0.resolvedStudentIDs.contains(student.id) }.map { $0.resolvedLessonID })
        plannedLessonIDs = Set(nextLessonsForStudent.map { $0.lessonID })
        // Note: masteredLessonIDs is loaded separately via loadMasteredLessonIDs() to avoid requiring modelContext here
    }

    func updateWorkModels(_ workModels: [WorkModel]) {
        // Set and compute summary
        self.workModelsForStudent = workModels
        self.workSummary = Self.computeWorkSummary(workModels: workModels)
    }

    private static func computeWorkSummary(workModels: [WorkModel]) -> WorkSummary {
        var practice = Set<UUID>()
        var follow = Set<UUID>()
        var pending = Set<UUID>()

        for work in workModels where work.status != .complete {
            guard let lid = UUID(uuidString: work.lessonID) else { continue }
            if let k = work.kind {
                switch k {
                case .practiceLesson: practice.insert(lid)
                case .followUpAssignment: follow.insert(lid)
                case .research, .report: break
                }
            }
            // Loose pending: no dueAt means pending
            if work.dueAt == nil { pending.insert(lid) }
        }
        return WorkSummary(practiceLessonIDs: practice, followUpLessonIDs: follow, pendingLessonIDs: pending)
    }

    // MARK: - Types
    struct WorkSummary {
        let practiceLessonIDs: Set<UUID>
        let followUpLessonIDs: Set<UUID>
        let pendingLessonIDs: Set<UUID>

        static let empty = WorkSummary(
            practiceLessonIDs: [],
            followUpLessonIDs: [],
            pendingLessonIDs: []
        )
    }

    // MARK: - UI Actions moved from View
    func showToast(_ message: String) {
        // Delegate to centralized ToastService
        ToastService.shared.showInfo(message)
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

    func ensureStudentLesson(for lesson: Lesson, modelContext: ModelContext, saveCoordinator: SaveCoordinator) -> StudentLesson {
        if let existing = latestStudentLesson(for: lesson.id, studentID: student.id) {
            return existing
        }
        let created = StudentLessonFactory.insertUnscheduled(
            lessonID: lesson.id,
            studentIDs: [student.id],
            into: modelContext
        )
        saveCoordinator.save(modelContext, reason: "Creating student lesson")
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
        let studentIDString = student.id.uuidString
        // CloudKit compatibility: lessonID is now String, convert UUID to String for comparison
        let lessonIDString = lesson.id.uuidString
        let presented = studentLessonsByID.values
            .filter { $0.lessonID == lessonIDString && $0.studentIDs.contains(studentIDString) && $0.isPresented }
            .sorted(by: { ($0.givenAt ?? $0.createdAt) > ($1.givenAt ?? $1.createdAt) })
        if let sl = presented.first {
            selectedStudentLessonForDetail = sl
        } else {
            selectedLessonForGive = lesson
            giveStartGiven = true
        }
    }

    func togglePresented(for lesson: Lesson, modelContext: ModelContext, saveCoordinator: SaveCoordinator) {
        if presentedLessonIDs.contains(lesson.id) {
            openMastered(for: lesson, modelContext: modelContext)
            return
        }
        if let upcoming = upcomingStudentLesson(for: lesson.id, studentID: student.id) {
            upcoming.isPresented = true
            saveCoordinator.save(modelContext, reason: "Recording presentation")
            // Auto-enroll in track if lesson belongs to a track
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: lesson,
                studentIDs: [student.id.uuidString],
                modelContext: modelContext,
                saveCoordinator: saveCoordinator
            )
        } else {
            let sl = StudentLessonFactory.makePresented(
                lessonID: lesson.id,
                studentIDs: [student.id]
            )
            sl.isPresented = true
            modelContext.insert(sl)
            if saveCoordinator.save(modelContext, reason: "Recording presentation") {
                showToast("Presentation recorded")
            }
            // Auto-enroll in track if lesson belongs to a track
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: lesson,
                studentIDs: [student.id.uuidString],
                modelContext: modelContext,
                saveCoordinator: saveCoordinator
            )
        }
    }

    // MARK: - Business Logic (moved from View)

    /// Fetch work models for the student (non-complete only)
    func fetchWorkModelsForStudent(modelContext: ModelContext) -> [WorkModel] {
        let sid = student.id.uuidString
        let completeStatusRaw = WorkStatus.complete.rawValue

        let predicate = #Predicate<WorkModel> { work in
            work.studentID == sid && work.statusRaw != completeStatusRaw
        }
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: predicate,
            sortBy: [SortDescriptor(\WorkModel.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Create a draft student lesson, reusing existing if available
    func createDraftStudentLesson(for lesson: Lesson, modelContext: ModelContext, saveCoordinator: SaveCoordinator) -> StudentLesson {
        // Reuse an existing unscheduled entry for this lesson+student if it exists
        if let existing = studentLessons.first(where: {
            $0.resolvedLessonID == lesson.id &&
            $0.scheduledFor == nil &&
            !$0.isGiven &&
            Set($0.resolvedStudentIDs) == Set([student.id])
        }) {
            return existing
        }

        let newSL: StudentLesson
        if giveStartGiven {
            newSL = StudentLessonFactory.makePresented(lessonID: lesson.id, studentIDs: [student.id])
        } else {
            newSL = StudentLessonFactory.makeUnscheduled(lessonID: lesson.id, studentIDs: [student.id])
        }
        newSL.students = [student]
        modelContext.insert(newSL)
        saveCoordinator.save(modelContext, reason: "Creating draft student lesson")

        // Auto-enroll in track if lesson is created as presented and belongs to a track
        if giveStartGiven {
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: lesson,
                studentIDs: [student.id.uuidString],
                modelContext: modelContext,
                saveCoordinator: saveCoordinator
            )
        }

        return newSL
    }

    /// Create or reuse a non-given student lesson
    func createOrReuseNonGivenStudentLesson(for lesson: Lesson, modelContext: ModelContext, saveCoordinator: SaveCoordinator) -> StudentLesson {
        if let existing = studentLessons.first(where: {
            $0.resolvedLessonID == lesson.id &&
            !$0.isGiven &&
            Set($0.resolvedStudentIDs) == Set([student.id])
        }) {
            return existing
        }

        let newSL = StudentLessonFactory.makeUnscheduled(lessonID: lesson.id, studentIDs: [student.id])
        newSL.students = [student]
        modelContext.insert(newSL)
        saveCoordinator.save(modelContext, reason: "Creating student lesson")

        return newSL
    }

    /// Log a presentation for a lesson
    func logPresentation(for lesson: Lesson, modelContext: ModelContext, saveCoordinator: SaveCoordinator) -> StudentLesson {
        let newSL = StudentLessonFactory.makePresented(lessonID: lesson.id, studentIDs: [student.id])
        newSL.isPresented = true
        newSL.students = [student]
        modelContext.insert(newSL)
        saveCoordinator.save(modelContext, reason: "Logging presentation")

        // Auto-enroll in track if lesson belongs to a track
        GroupTrackService.autoEnrollInTrackIfNeeded(
            lesson: lesson,
            studentIDs: [student.id.uuidString],
            modelContext: modelContext,
            saveCoordinator: saveCoordinator
        )

        return newSL
    }

    /// Ensure work exists for a lesson, creating WorkModel if needed
    func ensureWork(for lesson: Lesson, presentationStudentLesson: StudentLesson?, modelContext: ModelContext) -> WorkModel? {
        // Check for existing WorkModel first
        let studentLessonID = presentationStudentLesson?.id
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue

        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.studentLessonID == studentLessonID &&
                (work.statusRaw == activeRaw || work.statusRaw == reviewRaw)
            }
        )
        let existingWork = (try? modelContext.fetch(descriptor))?.first

        if let existing = existingWork {
            return existing
        }

        // Create new WorkModel
        let repository = WorkRepository(context: modelContext)
        do {
            return try repository.createWork(
                studentID: student.id,
                lessonID: lesson.id,
                title: nil,
                kind: nil,
                presentationID: presentationStudentLesson?.id,
                scheduledDate: nil
            )
        } catch {
            return nil
        }
    }

    /// Fetch a WorkModel by ID
    func fetchWork(by id: UUID, modelContext: ModelContext) -> WorkModel? {
        let descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate<WorkModel> { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }
}
