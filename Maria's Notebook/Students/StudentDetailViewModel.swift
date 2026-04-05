// swiftlint:disable file_length
// StudentDetailViewModel.swift
// View model for StudentDetailView. Manages caches, selections, and derived summaries.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import OSLog
import SwiftUI
import CoreData

/// View model backing StudentDetailView.
/// Builds in-memory caches and exposes selection state for sheets.
/// All methods maintain existing behavior; this refactor adds structure and docs only.
@Observable
@MainActor
// swiftlint:disable:next type_body_length
final class StudentDetailViewModel {
    private static let logger = Logger.students

    // MARK: - Properties
    let student: CDStudent

    // MARK: - Caches
    private(set) var lessons: [CDLesson] = []
    private(set) var lessonAssignments: [CDLessonAssignment] = []
    private(set) var lessonsByID: [UUID: CDLesson] = [:]
    private(set) var lessonAssignmentsByID: [UUID: CDLessonAssignment] = [:]
    private(set) var nextLessonsForStudent: [LessonAssignmentSnapshot] = []
    /// Lessons that have been presented to this student
    private(set) var presentedLessonIDs: Set<UUID> = []
    /// Lessons that this student has mastered (based on CDLessonPresentation.state == .proficient)
    private(set) var proficientLessonIDs: Set<UUID> = []
    private(set) var plannedLessonIDs: Set<UUID> = []

    private(set) var workModelsForStudent: [CDWorkModel] = []
    private(set) var workSummary: WorkSummary = .empty

    // MARK: - UI State
    // UI selection and toast state moved from the view
    var selectedLessonForGive: CDLesson?
    var giveStartGiven: Bool = false
    var selectedLessonAssignmentForDetail: CDLessonAssignment?
    var toastMessage: String?

    private let dependencies: AppDependencies
    
    // MARK: - Initialization
    init(student: CDStudent, dependencies: AppDependencies) {
        self.student = student
        self.dependencies = dependencies
    }

    // MARK: - Data Loading
    /// Load lessons and lesson assignments from the database using NSFetchRequest.
    func loadData(viewContext: NSManagedObjectContext) {
        let laDescriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        laDescriptor.sortDescriptors = [
                NSSortDescriptor(keyPath: \CDLessonAssignment.scheduledFor, ascending: true),
                NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: true)
            ]
        let allLAs = safeFetch(laDescriptor, context: viewContext)
        let studentID = student.id ?? UUID()
        let filteredLAs = allLAs.filter { $0.resolvedStudentIDs.contains(studentID) }

        let neededLessonIDs = Set(filteredLAs.map(\.resolvedLessonID))
        let fetchedLessons: [CDLesson]
        if !neededLessonIDs.isEmpty {
            let descriptor = NSFetchRequest<CDLesson>(entityName: "Lesson")
            descriptor.fetchLimit = 1000
            let allLessons = viewContext.safeFetch(descriptor)
            fetchedLessons = allLessons.filter { $0.id != nil && neededLessonIDs.contains($0.id!) }
        } else {
            fetchedLessons = []
        }

        self.lessons = fetchedLessons
        self.lessonAssignments = filteredLAs

        updateData(lessons: fetchedLessons, lessonAssignments: filteredLAs)
        loadProficientLessonIDs(viewContext: viewContext)
    }

    /// Loads lesson IDs that have been mastered by this student from CDLessonPresentation records.
    private func loadProficientLessonIDs(viewContext: NSManagedObjectContext) {
        let studentIDString = student.id?.uuidString ?? ""
        // PERFORMANCE: Use predicate to filter at database level instead of loading all records
        // CDNote: Must use stateRaw (stored property) not state (computed property) in predicates
        let proficientStateRaw = LessonPresentationState.proficient.rawValue
        let descriptor: NSFetchRequest<CDLessonPresentation> = NSFetchRequest(entityName: "LessonPresentation")
        descriptor.predicate = NSPredicate(format: "studentID == %@ AND stateRaw == %@", studentIDString, proficientStateRaw)
        let proficientPresentations = safeFetch(descriptor, context: viewContext)

        proficientLessonIDs = Set(
            proficientPresentations.compactMap { UUID(uuidString: $0.lessonID) }
        )
    }

    // MARK: - Public API
    func updateData(lessons: [CDLesson], lessonAssignments: [CDLessonAssignment]) {
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        lessonsByID = Dictionary(lessons.uniqueByID.compactMap { l in l.id.map { ($0, l) } }, uniquingKeysWith: { first, _ in first })
        lessonAssignmentsByID = Dictionary(
            lessonAssignments.uniqueByID.compactMap { la in la.id.map { ($0, la) } },
            uniquingKeysWith: { first, _ in first }
        )

        // Next lessons for this student (not yet presented)
        let studentID = student.id ?? UUID()
        let upcoming = lessonAssignments.filter { $0.resolvedStudentIDs.contains(studentID) && !$0.isPresented }
        let sorted = upcoming.sorted { lhs, rhs in
            switch (lhs.scheduledFor, rhs.scheduledFor) {
            case let (l?, r?):
                return l < r
            case (nil, nil):
                return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
        nextLessonsForStudent = sorted.map { $0.snapshot() }

        presentedLessonIDs = Set(
            lessonAssignments
                .filter { $0.isPresented && $0.resolvedStudentIDs.contains(studentID) }
                .map(\.resolvedLessonID)
        )
        plannedLessonIDs = Set(nextLessonsForStudent.map(\.lessonID))
    }

    func updateWorkModels(_ workModels: [CDWorkModel]) {
        // Set and compute summary
        self.workModelsForStudent = workModels
        self.workSummary = Self.computeWorkSummary(workModels: workModels)
    }

    private static func computeWorkSummary(workModels: [CDWorkModel]) -> WorkSummary {
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
        _ descriptor: NSFetchRequest<T>,
        context: NSManagedObjectContext,
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

    func latestLessonAssignment(for lessonID: UUID, studentID: UUID) -> CDLessonAssignment? {
        let matches = lessonAssignmentsByID.values.filter {
            $0.resolvedLessonID == lessonID && $0.resolvedStudentIDs.contains(studentID)
        }
        return matches.sorted { lhs, rhs in
            let lDate = lhs.presentedAt ?? lhs.scheduledFor ?? lhs.createdAt ?? .distantPast
            let rDate = rhs.presentedAt ?? rhs.scheduledFor ?? rhs.createdAt ?? .distantPast
            return lDate > rDate
        }.first
    }

    func upcomingLessonAssignment(for lessonID: UUID, studentID: UUID) -> CDLessonAssignment? {
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
                return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }.first
    }

    func ensureLessonAssignment(
        for lesson: CDLesson, viewContext: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) -> CDLessonAssignment {
        if let lessonID = lesson.id, let studentID = student.id,
           let existing = latestLessonAssignment(for: lessonID, studentID: studentID) {
            return existing
        }
        let created = PresentationFactory.makeDraft(
            lessonID: lesson.id ?? UUID(),
            studentIDs: [student.id ?? UUID()],
            context: viewContext
        )
        saveCoordinator.save(viewContext, reason: "Creating lesson assignment")
        return created
    }

    func openPlan(for lesson: CDLesson, viewContext: NSManagedObjectContext) {
        if let lessonID = lesson.id, let studentID = student.id,
           let la = upcomingLessonAssignment(for: lessonID, studentID: studentID) {
            selectedLessonAssignmentForDetail = la
        } else {
            selectedLessonForGive = lesson
            giveStartGiven = false
        }
    }

    func openProficient(for lesson: CDLesson, viewContext: NSManagedObjectContext) {
        let studentIDString = student.id?.uuidString ?? ""
        let lessonIDString = lesson.id?.uuidString ?? ""
        let presented = lessonAssignmentsByID.values
            .filter { $0.lessonID == lessonIDString && $0.studentIDs.contains(studentIDString) && $0.isPresented }
            .sorted { ($0.presentedAt ?? $0.createdAt ?? .distantPast) > ($1.presentedAt ?? $1.createdAt ?? .distantPast) }
        if let la = presented.first {
            selectedLessonAssignmentForDetail = la
        } else {
            selectedLessonForGive = lesson
            giveStartGiven = true
        }
    }

    func togglePresented(for lesson: CDLesson, viewContext: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        guard let lessonID = lesson.id, let studentID = student.id else { return }
        if presentedLessonIDs.contains(lessonID) {
            openProficient(for: lesson, viewContext: viewContext)
            return
        }
        let presentedDate = AppCalendar.startOfDay(Date())
        if let upcoming = upcomingLessonAssignment(for: lessonID, studentID: studentID) {
            upcoming.markPresented(at: presentedDate)
            saveCoordinator.save(viewContext, reason: "Recording presentation")
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lessonSubject: lesson.subject,
                lessonGroup: lesson.group,
                studentIDs: [studentID.uuidString],
                context: viewContext,
                saveCoordinator: saveCoordinator
            )
        } else {
            let la = PresentationFactory.makePresented(
                lessonID: lessonID,
                studentIDs: [studentID],
                presentedAt: presentedDate,
                context: viewContext
            )
            la.lesson = lesson
            la.syncSnapshotsFromRelationships()
            if saveCoordinator.save(viewContext, reason: "Recording presentation") {
                showToast("Presentation recorded")
            }
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lessonSubject: lesson.subject,
                lessonGroup: lesson.group,
                studentIDs: [studentID.uuidString],
                context: viewContext,
                saveCoordinator: saveCoordinator
            )
        }
    }

    // MARK: - Business Logic (moved from View)

    /// Fetch work models for the student (non-complete only)
    func fetchWorkModelsForStudent(viewContext: NSManagedObjectContext) -> [CDWorkModel] {
        let sid = student.id?.uuidString ?? ""
        let completeStatusRaw = WorkStatus.complete.rawValue

        let predicate = NSPredicate(format: "studentID == %@ AND statusRaw != %@", sid, completeStatusRaw)
        let descriptor: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
        descriptor.predicate = predicate
        descriptor.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)]
        descriptor.fetchLimit = 500 // Reasonable limit for incomplete work per student
        return safeFetch(descriptor, context: viewContext)
    }

    /// Create a draft lesson assignment, reusing existing if available
    func createDraftLessonAssignment(
        for lesson: CDLesson, viewContext: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) -> CDLessonAssignment {
        // Reuse an existing unscheduled entry for this lesson+student if it exists
        let lessonID = lesson.id ?? UUID()
        let studentID = student.id ?? UUID()
        if let existing = lessonAssignments.first(where: {
            $0.resolvedLessonID == lessonID &&
            $0.scheduledFor == nil &&
            !$0.isPresented &&
            Set($0.resolvedStudentIDs) == Set([studentID])
        }) {
            return existing
        }

        let newLA: CDLessonAssignment
        if giveStartGiven {
            newLA = PresentationFactory.makePresented(
                lessonID: lessonID,
                studentIDs: [studentID],
                presentedAt: AppCalendar.startOfDay(Date()),
                context: viewContext
            )
        } else {
            newLA = PresentationFactory.makeDraft(
                lessonID: lessonID,
                studentIDs: [studentID],
                context: viewContext
            )
        }
        newLA.lesson = lesson
        // students stored as studentIDs array, already set by PresentationFactory
        newLA.syncSnapshotsFromRelationships()
        viewContext.insert(newLA)
        saveCoordinator.save(viewContext, reason: "Creating draft lesson assignment")

        if giveStartGiven {
            GroupTrackService.autoEnrollInTrackIfNeeded(
                lessonSubject: lesson.subject,
                lessonGroup: lesson.group,
                studentIDs: [studentID.uuidString],
                context: viewContext,
                saveCoordinator: saveCoordinator
            )
        }

        return newLA
    }

    /// Create or reuse a non-presented lesson assignment
    func createOrReuseUpcomingLessonAssignment(
        for lesson: CDLesson, viewContext: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) -> CDLessonAssignment {
        let lessonID = lesson.id ?? UUID()
        let studentID = student.id ?? UUID()
        if let existing = lessonAssignments.first(where: {
            $0.resolvedLessonID == lessonID &&
            !$0.isPresented &&
            Set($0.resolvedStudentIDs) == Set([studentID])
        }) {
            return existing
        }

        let newLA = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [studentID], context: viewContext)
        newLA.lesson = lesson
        saveCoordinator.save(viewContext, reason: "Creating lesson assignment")

        return newLA
    }

    /// Log a presentation for a lesson
    func logPresentation(
        for lesson: CDLesson, viewContext: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) -> CDLessonAssignment {
        let lessonID = lesson.id ?? UUID()
        let studentID = student.id ?? UUID()
        let presentedDate = AppCalendar.startOfDay(Date())
        let newLA = PresentationFactory.makePresented(
            lessonID: lessonID,
            studentIDs: [studentID],
            presentedAt: presentedDate,
            context: viewContext
        )
        newLA.lesson = lesson
        newLA.syncSnapshotsFromRelationships()
        viewContext.insert(newLA)
        saveCoordinator.save(viewContext, reason: "Logging presentation")

        GroupTrackService.autoEnrollInTrackIfNeeded(
            lessonSubject: lesson.subject,
            lessonGroup: lesson.group,
            studentIDs: [studentID.uuidString],
            context: viewContext,
            saveCoordinator: saveCoordinator
        )

        return newLA
    }

    /// Ensure work exists for a lesson, creating CDWorkModel if needed
    func ensureWork(for lesson: CDLesson, lessonAssignment: CDLessonAssignment?, viewContext: NSManagedObjectContext) -> CDWorkModel? {
        let presentationIDString = lessonAssignment?.id?.uuidString
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue

        let descriptor: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
        descriptor.predicate = NSPredicate(format: "presentationID == %@ AND (statusRaw == %@ OR statusRaw == %@)", presentationIDString ?? "", activeRaw, reviewRaw)
        let limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = 1
        let existingWork = safeFetch(limitedDescriptor, context: viewContext).first

        if let existing = existingWork {
            return existing
        }

        let cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        let repository = WorkRepository(context: cdContext)
        do {
            guard let studentID = student.id, let lessonID = lesson.id else { return nil }
            let cdWork = try repository.createWork(
                studentID: studentID,
                lessonID: lessonID,
                title: nil,
                kind: nil,
                presentationID: lessonAssignment?.id,
                scheduledDate: nil
            )
            cdContext.safeSave()
            // Re-fetch as SwiftData CDWorkModel (both contexts share the same SQLite store)
            let workID = cdWork.id ?? UUID()
            let refetch = { let r = NSFetchRequest<CDWorkModel>(entityName: "WorkModel"); r.predicate = NSPredicate(format: "id == %@", workID as CVarArg); r.fetchLimit = 1; return r }()
            return try? viewContext.fetch(refetch).first
        } catch {
            return nil
        }
    }

    /// Fetch a CDWorkModel by ID
    func fetchWork(by id: UUID, viewContext: NSManagedObjectContext) -> CDWorkModel? {
        let descriptor = { let r = NSFetchRequest<CDWorkModel>(entityName: "WorkModel"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); r.fetchLimit = 1; return r }()
        return safeFetch(descriptor, context: viewContext).first
    }
}
