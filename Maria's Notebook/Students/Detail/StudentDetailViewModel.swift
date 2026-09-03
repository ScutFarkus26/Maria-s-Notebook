// StudentDetailViewModel.swift
// View model for StudentDetailView. Manages caches, selections, and derived summaries.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import SwiftUI
import CoreData

/// View model backing StudentDetailView.
/// Builds in-memory caches and exposes selection state for sheets.
/// All methods maintain existing behavior; this refactor adds structure and docs only.
@Observable
@MainActor
final class StudentDetailViewModel {
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
        let allLAs = viewContext.safeFetch(laDescriptor)
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
        descriptor.predicate = NSPredicate(
            format: "studentID == %@ AND stateRaw == %@",
            studentIDString,
            proficientStateRaw
        )
        let proficientPresentations = viewContext.safeFetch(descriptor)

        proficientLessonIDs = Set(
            proficientPresentations.compactMap { UUID(uuidString: $0.lessonID) }
        )
    }

    // MARK: - Public API
    func updateData(lessons: [CDLesson], lessonAssignments: [CDLessonAssignment]) {
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        lessonsByID = Dictionary(
            lessons.uniqueByID.compactMap { l in l.id.map { ($0, l) } },
            uniquingKeysWith: { first, _ in first }
        )
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

    // MARK: - UI Actions moved from View
    func showToast(_ message: String) {
        // Delegate to centralized ToastService
        dependencies.toastService.showInfo(message)
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
        // Prefetch unifiedNotes so StudentOverviewTab's needsAttention/latestNoteDate
        // reads each work's notes from the row cache instead of faulting per row (N+1).
        descriptor.relationshipKeyPathsForPrefetching = ["unifiedNotes"]
        return viewContext.safeFetch(descriptor)
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
            SequenceTrackService.autoEnrollInTrackIfNeeded(
                lessonArea: lesson.area,
                lessonSequence: lesson.sequence,
                studentIDs: [studentID.uuidString],
                context: viewContext,
                saveCoordinator: saveCoordinator
            )
        }

        return newLA
    }

}
