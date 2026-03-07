// swiftlint:disable file_length
// StudentDetailViewModel.swift
// View model for StudentDetailView. Manages caches, selections, and derived summaries.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import OSLog
import SwiftData
import SwiftUI

/// View model backing StudentDetailView.
/// Builds in-memory caches and exposes selection state for sheets.
/// All methods maintain existing behavior; this refactor adds structure and docs only.
@Observable
@MainActor
// swiftlint:disable:next type_body_length
final class StudentDetailViewModel {
    private static let logger = Logger.students

    // MARK: - Properties
    let student: Student

    // MARK: - Caches
    private(set) var lessons: [Lesson] = []
    private(set) var lessonAssignments: [LessonAssignment] = []
    private(set) var lessonsByID: [UUID: Lesson] = [:]
    private(set) var lessonAssignmentsByID: [UUID: LessonAssignment] = [:]
    private(set) var nextLessonsForStudent: [LessonAssignmentSnapshot] = []
    /// Lessons that have been presented to this student
    private(set) var presentedLessonIDs: Set<UUID> = []
    /// Lessons that this student has mastered (based on LessonPresentation.state == .proficient)
    private(set) var proficientLessonIDs: Set<UUID> = []
    private(set) var plannedLessonIDs: Set<UUID> = []

    private(set) var workModelsForStudent: [WorkModel] = []
    private(set) var workSummary: WorkSummary = .empty

    // MARK: - UI State
    // UI selection and toast state moved from the view
    var selectedLessonForGive: Lesson?
    var giveStartGiven: Bool = false
    var selectedLessonAssignmentForDetail: LessonAssignment?
    var toastMessage: String?

    private let dependencies: AppDependencies
    
    // MARK: - Initialization
    init(student: Student, dependencies: AppDependencies) {
        self.student = student
        self.dependencies = dependencies
    }

    // MARK: - Data Loading
    /// Load lessons and lesson assignments from the database using FetchDescriptor.
    func loadData(modelContext: ModelContext) {
        let laDescriptor = FetchDescriptor<LessonAssignment>(
            sortBy: [
                SortDescriptor(\LessonAssignment.scheduledFor, order: .forward),
                SortDescriptor(\LessonAssignment.createdAt, order: .forward)
            ]
        )
        let allLAs = safeFetch(laDescriptor, context: modelContext)
        let filteredLAs = allLAs.filter { $0.resolvedStudentIDs.contains(student.id) }

        let neededLessonIDs = Set(filteredLAs.map { $0.resolvedLessonID })
        let fetchedLessons: [Lesson]
        if !neededLessonIDs.isEmpty {
            var descriptor = FetchDescriptor<Lesson>()
            descriptor.fetchLimit = 1000
            let allLessons = modelContext.safeFetch(descriptor)
            fetchedLessons = allLessons.filter { neededLessonIDs.contains($0.id) }
        } else {
            fetchedLessons = []
        }

        self.lessons = fetchedLessons
        self.lessonAssignments = filteredLAs

        updateData(lessons: fetchedLessons, lessonAssignments: filteredLAs)
        loadProficientLessonIDs(modelContext: modelContext)
    }

    /// Loads lesson IDs that have been mastered by this student from LessonPresentation records.
    private func loadProficientLessonIDs(modelContext: ModelContext) {
        let studentIDString = student.id.uuidString
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        // Note: Must use stateRaw (stored property) not state (computed property) in predicates
        let proficientStateRaw = LessonPresentationState.proficient.rawValue
        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate { lp in
                lp.studentID == studentIDString && lp.stateRaw == proficientStateRaw
            }
        )
        let proficientPresentations = safeFetch(descriptor, context: modelContext)

        proficientLessonIDs = Set(
            proficientPresentations.compactMap { UUID(uuidString: $0.lessonID) }
        )
    }

    // MARK: - Public API
    func updateData(lessons: [Lesson], lessonAssignments: [LessonAssignment]) {
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        lessonsByID = Dictionary(lessons.uniqueByID.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lessonAssignmentsByID = Dictionary(
            lessonAssignments.uniqueByID.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Next lessons for this student (not yet presented)
        let upcoming = lessonAssignments.filter { $0.resolvedStudentIDs.contains(student.id) && !$0.isPresented }
        let sorted = upcoming.sorted { lhs, rhs in
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
        nextLessonsForStudent = sorted.map { $0.snapshot() }

        presentedLessonIDs = Set(
            lessonAssignments
                .filter { $0.isPresented && $0.resolvedStudentIDs.contains(student.id) }
                .map { $0.resolvedLessonID }
        )
        plannedLessonIDs = Set(nextLessonsForStudent.map { $0.lessonID })
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

    // MARK: - Error Handling Helpers

    private func safeFetch<T>(
        _ descriptor: FetchDescriptor<T>,
        context: ModelContext,
        functionName: String = #function
    ) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.warning(
                "Failed to fetch \(T.self, privacy: .public) in \(functionName, privacy: .public): \(error)"
            )
            return []
        }
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
        dependencies.toastService.showInfo(message)
    }

    func latestLessonAssignment(for lessonID: UUID, studentID: UUID) -> LessonAssignment? {
        let matches = lessonAssignmentsByID.values.filter {
            $0.resolvedLessonID == lessonID && $0.resolvedStudentIDs.contains(studentID)
        }
        return matches.sorted { lhs, rhs in
            let lDate = lhs.presentedAt ?? lhs.scheduledFor ?? lhs.createdAt
            let rDate = rhs.presentedAt ?? rhs.scheduledFor ?? rhs.createdAt
            return lDate > rDate
        }.first
    }

    func upcomingLessonAssignment(for lessonID: UUID, studentID: UUID) -> LessonAssignment? {
        let matches = lessonAssignmentsByID.values.filter {
            $0.resolvedLessonID == lessonID
                && $0.resolvedStudentIDs.contains(studentID)
                && !$0.isPresented
        }
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

    func ensureLessonAssignment(
        for lesson: Lesson, modelContext: ModelContext,
        saveCoordinator: SaveCoordinator
    ) -> LessonAssignment {
        if let existing = latestLessonAssignment(for: lesson.id, studentID: student.id) {
            return existing
        }
        let created = PresentationFactory.insertDraft(
            lessonID: lesson.id,
            studentIDs: [student.id],
            context: modelContext
        )
        saveCoordinator.save(modelContext, reason: "Creating lesson assignment")
        return created
    }

    func openPlan(for lesson: Lesson, modelContext: ModelContext) {
        if let la = upcomingLessonAssignment(for: lesson.id, studentID: student.id) {
            selectedLessonAssignmentForDetail = la
        } else {
            selectedLessonForGive = lesson
            giveStartGiven = false
        }
    }

    func openProficient(for lesson: Lesson, modelContext: ModelContext) {
        let studentIDString = student.id.uuidString
        let lessonIDString = lesson.id.uuidString
        let presented = lessonAssignmentsByID.values
            .filter { $0.lessonID == lessonIDString && $0.studentIDs.contains(studentIDString) && $0.isPresented }
            .sorted(by: { ($0.presentedAt ?? $0.createdAt) > ($1.presentedAt ?? $1.createdAt) })
        if let la = presented.first {
            selectedLessonAssignmentForDetail = la
        } else {
            selectedLessonForGive = lesson
            giveStartGiven = true
        }
    }

    func togglePresented(for lesson: Lesson, modelContext: ModelContext, saveCoordinator: SaveCoordinator) {
        if presentedLessonIDs.contains(lesson.id) {
            openProficient(for: lesson, modelContext: modelContext)
            return
        }
        let presentedDate = AppCalendar.startOfDay(Date())
        if let upcoming = upcomingLessonAssignment(for: lesson.id, studentID: student.id) {
            upcoming.markPresented(at: presentedDate)
            saveCoordinator.save(modelContext, reason: "Recording presentation")
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: lesson,
                studentIDs: [student.id.uuidString],
                modelContext: modelContext,
                saveCoordinator: saveCoordinator
            )
        } else {
            let la = PresentationFactory.makePresented(
                lessonID: lesson.id,
                studentIDs: [student.id],
                presentedAt: presentedDate
            )
            la.lesson = lesson
            la.students = [student]
            la.syncSnapshotsFromRelationships()
            modelContext.insert(la)
            if saveCoordinator.save(modelContext, reason: "Recording presentation") {
                showToast("Presentation recorded")
            }
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
        var descriptor = FetchDescriptor<WorkModel>(
            predicate: predicate,
            sortBy: [SortDescriptor(\WorkModel.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500 // Reasonable limit for incomplete work per student
        return safeFetch(descriptor, context: modelContext)
    }

    /// Create a draft lesson assignment, reusing existing if available
    func createDraftLessonAssignment(
        for lesson: Lesson, modelContext: ModelContext,
        saveCoordinator: SaveCoordinator
    ) -> LessonAssignment {
        // Reuse an existing unscheduled entry for this lesson+student if it exists
        if let existing = lessonAssignments.first(where: {
            $0.resolvedLessonID == lesson.id &&
            $0.scheduledFor == nil &&
            !$0.isPresented &&
            Set($0.resolvedStudentIDs) == Set([student.id])
        }) {
            return existing
        }

        let newLA: LessonAssignment
        if giveStartGiven {
            newLA = PresentationFactory.makePresented(
                lessonID: lesson.id,
                studentIDs: [student.id],
                presentedAt: AppCalendar.startOfDay(Date())
            )
        } else {
            newLA = PresentationFactory.makeDraft(
                lessonID: lesson.id,
                studentIDs: [student.id]
            )
        }
        newLA.lesson = lesson
        newLA.students = [student]
        newLA.syncSnapshotsFromRelationships()
        modelContext.insert(newLA)
        saveCoordinator.save(modelContext, reason: "Creating draft lesson assignment")

        if giveStartGiven {
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lesson: lesson,
                studentIDs: [student.id.uuidString],
                modelContext: modelContext,
                saveCoordinator: saveCoordinator
            )
        }

        return newLA
    }

    /// Create or reuse a non-presented lesson assignment
    func createOrReuseUpcomingLessonAssignment(
        for lesson: Lesson, modelContext: ModelContext,
        saveCoordinator: SaveCoordinator
    ) -> LessonAssignment {
        if let existing = lessonAssignments.first(where: {
            $0.resolvedLessonID == lesson.id &&
            !$0.isPresented &&
            Set($0.resolvedStudentIDs) == Set([student.id])
        }) {
            return existing
        }

        let newLA = PresentationFactory.makeDraft(lessonID: lesson.id, studentIDs: [student.id])
        newLA.lesson = lesson
        newLA.students = [student]
        modelContext.insert(newLA)
        saveCoordinator.save(modelContext, reason: "Creating lesson assignment")

        return newLA
    }

    /// Log a presentation for a lesson
    func logPresentation(
        for lesson: Lesson, modelContext: ModelContext,
        saveCoordinator: SaveCoordinator
    ) -> LessonAssignment {
        let presentedDate = AppCalendar.startOfDay(Date())
        let newLA = PresentationFactory.makePresented(
            lessonID: lesson.id,
            studentIDs: [student.id],
            presentedAt: presentedDate
        )
        newLA.lesson = lesson
        newLA.students = [student]
        newLA.syncSnapshotsFromRelationships()
        modelContext.insert(newLA)
        saveCoordinator.save(modelContext, reason: "Logging presentation")

        GroupTrackService.autoEnrollInTrackIfNeeded(
            lesson: lesson,
            studentIDs: [student.id.uuidString],
            modelContext: modelContext,
            saveCoordinator: saveCoordinator
        )

        return newLA
    }

    /// Ensure work exists for a lesson, creating WorkModel if needed
    func ensureWork(for lesson: Lesson, lessonAssignment: LessonAssignment?, modelContext: ModelContext) -> WorkModel? {
        let presentationIDString = lessonAssignment?.id.uuidString
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue

        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate { work in
                work.presentationID == presentationIDString &&
                (work.statusRaw == activeRaw || work.statusRaw == reviewRaw)
            }
        )
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = 1
        let existingWork = safeFetch(limitedDescriptor, context: modelContext).first

        if let existing = existingWork {
            return existing
        }

        let repository = WorkRepository(context: modelContext)
        do {
            return try repository.createWork(
                studentID: student.id,
                lessonID: lesson.id,
                title: nil,
                kind: nil,
                presentationID: lessonAssignment?.id,
                scheduledDate: nil
            )
        } catch {
            return nil
        }
    }

    /// Fetch a WorkModel by ID
    func fetchWork(by id: UUID, modelContext: ModelContext) -> WorkModel? {
        var descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate<WorkModel> { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetch(descriptor, context: modelContext).first
    }
}
