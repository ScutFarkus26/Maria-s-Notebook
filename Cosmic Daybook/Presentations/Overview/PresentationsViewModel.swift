// PresentationsViewModel.swift
// ViewModel to cache expensive blocking logic and optimize PresentationsView performance
// Preserves all existing functionality while improving responsiveness

import Foundation
import SwiftUI
import CoreData

@Observable
final class PresentationsViewModel {
    // MARK: - State
    var readyLessons: [CDLessonAssignment] = []
    var blockedLessons: [CDLessonAssignment] = []
    /// Per-assignment blocking results with per-student readiness.
    var blockingResults: [UUID: BlockingAlgorithmEngine.BlockingCheckResult] = [:]
    var daysSinceLastLessonByStudent: [UUID: Int] = [:]
    var lastAreaByStudent: [UUID: String] = [:]
    var openWorkCountByStudent: [UUID: Int] = [:]

    // Expose cached students for use in filteredSnapshot (avoids redundant fetching)
    var cachedStudents: [CDStudent] {
        self.cachedStudentsStorage
    }

    // Expose cached lessons for inbox filtering (avoids redundant fetching)
    var lessons: [CDLesson] {
        self.cachedLessons
    }

    /// Lookup dictionary rebuilt during `updateAsync` so filter/sort paths don't re-allocate.
    var lessonsByIDCache: [UUID: CDLesson] = [:]

    /// Lookup dictionary rebuilt during `updateAsync` so filter/sort paths don't re-allocate.
    var studentsByIDCache: [UUID: CDStudent] = [:]

    // MARK: - Dependencies
    var viewContext: NSManagedObjectContext?
    var calendar: Calendar = .current

    // MARK: - Cache State
    private var lastUpdateDate: Date?
    private var cachedLessons: [CDLesson] = []
    private var cachedWorkModels: [CDWorkModel] = []
    /// All non-given lesson assignments cached during update — used by chip-filter
    /// slices like `overdueReady` and `recentlyMissed`.
    var cachedLessonAssignments: [CDLessonAssignment] = []
    private var cachedStudentsStorage: [CDStudent] = []

    // PERFORMANCE: the pending update, kept so a newer one can cancel it
    private(set) var pendingUpdateTask: Task<Void, Never>?
    /// How many times `update` refetched the assignment table (tests pin the gate).
    @ObservationIgnored private(set) var assignmentFetchCount = 0

    // PERFORMANCE: Use hash-based change detection
    private var lastLessonAssignmentChangeHash: Int?
    private var lastLessonsHash: Int?
    private var lastWorkModelHash: Int?
    private var lastStudentsHash: Int?
    /// Order and test students (`settingsHash`).
    private var lastSettingsHash: Int?
    /// Sub-area default rules and the preceding lessons' mastery marks
    /// (`readinessInputsHash`).
    private var lastReadinessInputsHash: Int?

    /// Bumped on every `LessonAssignment` change the view context could see;
    /// the cached table and its hash stand in for a refetch only while stored
    /// at the current generation (see `+AssignmentGate`).
    @ObservationIgnored var assignmentsGeneration = 0
    @ObservationIgnored var cachedAssignmentsGeneration: Int?
    @ObservationIgnored weak var observedContext: NSManagedObjectContext?
    // `nonisolated(unsafe)` for the nonisolated `deinit`; written on the main actor only.
    @ObservationIgnored nonisolated(unsafe) var assignmentObservers: [NSObjectProtocol] = []

    // MARK: - Initialization
    init() {}

    deinit {
        assignmentObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Memory Pressure

    /// Releases every cached object graph this view model pins.
    ///
    /// The caches are lifetime-scoped — once `update` runs they hold lessons,
    /// students, work models, and assignments for as long as the view model
    /// lives. Under memory pressure that's worth giving back; the change-detection
    /// hashes and `lastUpdateDate` are cleared alongside them so the next `update`
    /// sees "changed" and refetches instead of short-circuiting on stale state.
    func clearCaches() {
        cachedLessons = []
        cachedWorkModels = []
        cachedLessonAssignments = []
        cachedStudentsStorage = []
        lessonsByIDCache = [:]
        studentsByIDCache = [:]
        blockingResults = [:]
        daysSinceLastLessonByStudent = [:]
        lastAreaByStudent = [:]
        openWorkCountByStudent = [:]
        readyLessons = []
        blockedLessons = []

        lastUpdateDate = nil
        cachedAssignmentsGeneration = nil
        lastLessonAssignmentChangeHash = nil
        lastLessonsHash = nil
        lastWorkModelHash = nil
        lastStudentsHash = nil
        lastSettingsHash = nil
        lastReadinessInputsHash = nil
    }

    // MARK: - Public API

    // Fetch data and update the view model.
    // PERFORMANCE: Runs asynchronously in background to avoid blocking the main thread
    // swiftlint:disable:next function_parameter_count
    func update(
        viewContext: NSManagedObjectContext,
        calendar: Calendar,
        inboxOrderRaw: String,
        showTestStudents: Bool,
        testStudentNamesRaw: String,
        lessons: [CDLesson],
        students: [CDStudent]
    ) {
        // Cancel any pending update task
        pendingUpdateTask?.cancel()

        // Launch async update in background
        pendingUpdateTask = Task { @MainActor in
            await updateAsync(
                viewContext: viewContext,
                calendar: calendar,
                inboxOrderRaw: inboxOrderRaw,
                showTestStudents: showTestStudents,
                testStudentNamesRaw: testStudentNamesRaw,
                lessons: lessons,
                students: students
            )
        }
    }

    // Internal async implementation of update logic
    // swiftlint:disable:next function_parameter_count function_body_length
    private func updateAsync(
        viewContext: NSManagedObjectContext,
        calendar: Calendar,
        inboxOrderRaw: String,
        showTestStudents: Bool,
        testStudentNamesRaw: String,
        lessons: [CDLesson],
        students: [CDStudent]
    ) async {
        self.viewContext = viewContext
        self.calendar = calendar
        observeAssignmentChanges(in: viewContext)

        // Unchanged assignments are the same live objects a refetch would
        // return, with the same hash; only refetch when one moved.
        let generation = assignmentsGeneration
        let (lessonAssignments, laHash): ([CDLessonAssignment], Int)
        if cachedAssignmentsGeneration == generation, let lastHash = lastLessonAssignmentChangeHash {
            (lessonAssignments, laHash) = (cachedLessonAssignments, lastHash)
        } else {
            lessonAssignments = fetchLessonAssignmentsData(from: viewContext)
            assignmentFetchCount += 1
            laHash = computeLessonAssignmentHash(lessonAssignments)
            await Task.yield()
            if Task.isCancelled { return }
        }

        let workRequest = CDFetchRequest(CDWorkModel.self)
        workRequest.predicate = WorkStatus.openPredicate
        workRequest.relationshipKeyPathsForPrefetching = ["participants"]
        let workModels = viewContext.safeFetch(workRequest)
        let closedPrecedingWork = fetchClosedPrecedingWork(lessonAssignments, lessons, in: viewContext)
        let masteryMarks = fetchPrecedingMasteryMarks(lessonAssignments, lessons, in: viewContext)
        await Task.yield()
        if Task.isCancelled { return }

        let lHash = Self.lessonsHash(lessons)
        let sHash = computeStudentsHash(students)
        let wHash = computeWorkModelHash(workModels + closedPrecedingWork)
        let settingsHash = Self.settingsHash(inboxOrderRaw, showTestStudents, testStudentNamesRaw)
        let readinessHash = Self.readinessInputsHash(
            sequenceSettings: viewContext.safeFetch(CDFetchRequest(CDLessonSequenceSettings.self)),
            masteryMarks: masteryMarks
        )
        let coreChanged = laHash != lastLessonAssignmentChangeHash
            || lHash != lastLessonsHash
            || sHash != lastStudentsHash
            || wHash != lastWorkModelHash
            || settingsHash != lastSettingsHash
            || readinessHash != lastReadinessInputsHash
        if !coreChanged && lastUpdateDate != nil {
            // Same hash as the cached array: it still stands for the store.
            cachedAssignmentsGeneration = generation
            return
        }

        lastLessonAssignmentChangeHash = laHash
        lastLessonsHash = lHash
        lastWorkModelHash = wHash
        lastStudentsHash = sHash
        lastSettingsHash = settingsHash
        lastReadinessInputsHash = readinessHash

        #if DEBUG
        PerformanceLogger.logScreenLoad(
            screenName: "PresentationsViewModel",
            itemCounts: [
                "lessonAssignments": lessonAssignments.count,
                "lessons": lessons.count,
                "students": students.count,
                "workModels": workModels.count
            ]
        )
        #endif

        cachedLessons = lessons
        cachedWorkModels = workModels
        cachedLessonAssignments = lessonAssignments
        cachedAssignmentsGeneration = generation
        lastUpdateDate = Date()

        let visibleStudents = TestStudentsFilter.filterVisible(
            students.filterEnrolled(), show: showTestStudents, namesRaw: testStudentNamesRaw
        )
        cachedStudentsStorage = visibleStudents

        // Rebuild lookup caches once per update so filter/sort paths are O(1) per access.
        lessonsByIDCache = Dictionary(
            lessons.compactMap { guard let id = $0.id else { return nil }; return (id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        studentsByIDCache = Dictionary(
            visibleStudents.compactMap { guard let id = $0.id else { return nil }; return (id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Count open work items per student for suggest-next scoring
        var workCounts: [UUID: Int] = [:]
        for work in workModels {
            guard let sid = UUID(uuidString: work.studentID) else { continue }
            workCounts[sid, default: 0] += 1
        }
        self.openWorkCountByStudent = workCounts

        calculateDaysSinceLastLesson(
            lessonAssignments: lessonAssignments, lessons: lessons, students: visibleStudents
        )
        await Task.yield()
        if Task.isCancelled { return }

        let partition = partitionIntoReadyAndBlocked(
            lessonAssignments: lessonAssignments,
            lessons: lessons,
            workModels: workModels + closedPrecedingWork,
            masteryMarks: masteryMarks,
            judgedStudentIDs: Set(visibleStudents.compactMap(\.id)),
            inboxOrderRaw: inboxOrderRaw
        )
        self.readyLessons = partition.ready
        self.blockedLessons = partition.blocked
        self.blockingResults = partition.blockingResultsMap
    }

    private func fetchLessonAssignmentsData(from viewContext: NSManagedObjectContext) -> [CDLessonAssignment] {
        #if DEBUG
        return PerformanceLogger.measure(
            screenName: "PresentationsViewModel - Fetch LessonAssignments",
            operation: { viewContext.safeFetch(CDFetchRequest(CDLessonAssignment.self)) }
        )
        #else
        return viewContext.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        #endif
    }

    // swiftlint:disable:next function_parameter_count
    private func partitionIntoReadyAndBlocked(
        lessonAssignments: [CDLessonAssignment],
        lessons: [CDLesson],
        workModels: [CDWorkModel],
        masteryMarks: [String: Set<String>],
        judgedStudentIDs: Set<UUID>,
        inboxOrderRaw: String
    ) -> PresentationPartition {
        let allUnscheduled = lessonAssignments.filter { $0.scheduledFor == nil && !$0.isGiven }
        let blockingResults = BlockingAlgorithmEngine.checkBlocking(
            forBatch: allUnscheduled,
            lessons: lessons,
            allLessonAssignments: lessonAssignments,
            workModels: workModels,
            masteryMarks: masteryMarks,
            judgedStudentIDs: judgedStudentIDs
        )
        var ready: [CDLessonAssignment] = []
        var blocked: [CDLessonAssignment] = []
        for la in allUnscheduled {
            let result = la.id.flatMap { blockingResults[$0] }
                ?? BlockingAlgorithmEngine.BlockingCheckResult(
                    isBlocked: false, prereqOpenCount: 0, perStudentReadiness: [:]
                )
            if result.isBlocked { blocked.append(la) } else { ready.append(la) }
        }
        let ordered = InboxOrderStore.orderedUnscheduled(from: ready, orderRaw: inboxOrderRaw)
        blocked.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        return PresentationPartition(ready: ordered, blocked: blocked,
                                     blockingResultsMap: blockingResults)
    }
}

// MARK: - Cache Query Helpers

extension PresentationsViewModel {
    /// The unscheduled inbox split in two, plus the blocking check each row was
    /// judged by — the three values `refresh` assigns straight onto the model.
    struct PresentationPartition {
        let ready: [CDLessonAssignment]
        let blocked: [CDLessonAssignment]
        let blockingResultsMap: [UUID: BlockingAlgorithmEngine.BlockingCheckResult]
    }

    /// The children holding up a brewing lesson, for the marker on their
    /// chips: the ones the readiness engine found not ready. A separate lookup
    /// used to find the earlier lesson's presentation only when it had exactly
    /// the same children, so a group drawn from two earlier groups showed no
    /// marker (bug hunt 2026-11-03 #9).
    func blockingStudentIDs(of la: CDLessonAssignment) -> Set<UUID> {
        guard let id = la.id, let result = blockingResults[id] else { return [] }
        return Set(result.perStudentReadiness.values.filter { !$0.isReady }.map(\.studentID))
    }

}
