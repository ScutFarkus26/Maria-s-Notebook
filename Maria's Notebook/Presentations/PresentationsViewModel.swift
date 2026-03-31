// PresentationsViewModel.swift
// ViewModel to cache expensive blocking logic and optimize PresentationsView performance
// Preserves all existing functionality while improving responsiveness

import Foundation
import SwiftUI
import CoreData

@Observable
@MainActor
final class PresentationsViewModel {
    // MARK: - State
    var readyLessons: [CDLessonAssignment] = []
    var blockedLessons: [CDLessonAssignment] = []
    var blockingWorkCache: [UUID: [UUID: CDWorkModel]] = [:]
    var daysSinceLastLessonByStudent: [UUID: Int] = [:]
    var lastSubjectByStudent: [UUID: String] = [:]
    var openWorkCountByStudent: [UUID: Int] = [:]

    // Expose cached students for use in filteredSnapshot (avoids redundant fetching)
    var cachedStudents: [CDStudent] {
        self.cachedStudentsStorage
    }

    // Expose cached lessons for inbox filtering (avoids redundant fetching)
    var lessons: [CDLesson] {
        self.cachedLessons
    }

    // MARK: - Dependencies
    var viewContext: NSManagedObjectContext?
    var calendar: Calendar = .current

    // MARK: - Cache State
    private var lastUpdateDate: Date?
    private var cachedLessons: [CDLesson] = []
    private var cachedWorkModels: [CDWorkModel] = []
    private var cachedLessonAssignments: [CDLessonAssignment] = []
    private var cachedStudentsStorage: [CDStudent] = []

    // PERFORMANCE: CDTrackEntity pending update for cancellation
    private var pendingUpdateTask: Task<Void, Never>?

    // PERFORMANCE: Use hash-based change detection
    private var lastLessonAssignmentChangeHash: Int?
    private var lastLessonsHash: Int?
    private var lastWorkModelHash: Int?
    private var lastStudentsHash: Int?

    // MARK: - Initialization
    init() {}

    // MARK: - Change Detection Helpers

    /// Computes a hash for CDLessonAssignment change detection
    private func computeLessonAssignmentHash(_ assignments: [CDLessonAssignment]) -> Int {
        var hasher = Hasher()
        for la in assignments {
            hasher.combine(la.id)
            hasher.combine(la.scheduledFor?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(la.presentedAt?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(la.stateRaw)
            hasher.combine(la.notes)
            hasher.combine(la.followUpWork)
            hasher.combine(la.studentIDs.joined(separator: ","))
            hasher.combine(la.needsPractice)
            hasher.combine(la.needsAnotherPresentation)
            hasher.combine(la.lessonID)
        }
        return hasher.finalize()
    }

    /// Computes a hash for array of Identifiable items
    private func computeIDHash<T: Identifiable>(_ items: [T]) -> Int where T.ID == UUID? {
        var hasher = Hasher()
        for item in items {
            hasher.combine(item.id)
        }
        return hasher.finalize()
    }

    /// Computes a hash for CDWorkModel change detection (includes status and presentation link)
    private func computeWorkModelHash(_ workModels: [CDWorkModel]) -> Int {
        var hasher = Hasher()
        for w in workModels {
            hasher.combine(w.id)
            hasher.combine(w.statusRaw)
            hasher.combine(w.presentationID)
        }
        return hasher.finalize()
    }

    // MARK: - Public API

    // Fetch data and update the view model.
    // PERFORMANCE: Runs asynchronously in background to avoid blocking the main thread
    // swiftlint:disable:next function_parameter_count
    func update(
        viewContext: NSManagedObjectContext,
        calendar: Calendar,
        inboxOrderRaw: String,
        missWindow: PresentationsMissWindow,
        showTestStudents: Bool,
        testStudentNamesRaw: String
    ) {
        // Cancel any pending update task
        pendingUpdateTask?.cancel()

        // Launch async update in background
        pendingUpdateTask = Task { @MainActor in
            await updateAsync(
                viewContext: viewContext,
                calendar: calendar,
                inboxOrderRaw: inboxOrderRaw,
                missWindow: missWindow,
                showTestStudents: showTestStudents,
                testStudentNamesRaw: testStudentNamesRaw
            )
        }
    }

    // Internal async implementation of update logic
    // swiftlint:disable:next function_parameter_count function_body_length
    private func updateAsync(
        viewContext: NSManagedObjectContext,
        calendar: Calendar,
        inboxOrderRaw: String,
        missWindow: PresentationsMissWindow,
        showTestStudents: Bool,
        testStudentNamesRaw: String
    ) async {
        self.viewContext = viewContext
        self.calendar = calendar

        let lessonAssignments = fetchLessonAssignmentsData(from: viewContext)
        await Task.yield()
        if Task.isCancelled { return }

        let lessons = fetchLessonsData(from: viewContext)
        await Task.yield()
        if Task.isCancelled { return }

        let students = fetchStudentsData(from: viewContext)
        await Task.yield()
        if Task.isCancelled { return }

        let workRequest = CDFetchRequest(CDWorkModel.self)
        workRequest.predicate = NSPredicate(format: "statusRaw != %@", "complete")
        let workModels = viewContext.safeFetch(workRequest)
        await Task.yield()
        if Task.isCancelled { return }

        let laHash = computeLessonAssignmentHash(lessonAssignments)
        let lHash = computeIDHash(lessons)
        let sHash = computeIDHash(students)
        let wHash = computeWorkModelHash(workModels)
        let coreChanged = laHash != lastLessonAssignmentChangeHash
            || lHash != lastLessonsHash
            || sHash != lastStudentsHash
            || wHash != lastWorkModelHash
        if !coreChanged && lastUpdateDate != nil { return }

        lastLessonAssignmentChangeHash = laHash
        lastLessonsHash = lHash
        lastWorkModelHash = wHash
        lastStudentsHash = sHash

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
        lastUpdateDate = Date()

        let visibleStudents = TestStudentsFilter.filterVisible(
            students.filter(\.isEnrolled), show: showTestStudents, namesRaw: testStudentNamesRaw
        )
        cachedStudentsStorage = visibleStudents

        // Count open work items per student for suggest-next scoring
        var workCounts: [UUID: Int] = [:]
        for work in workModels {
            guard let sid = UUID(uuidString: work.studentID) else { continue }
            workCounts[sid, default: 0] += 1
        }
        self.openWorkCountByStudent = workCounts

        let openWorkByPresentationID: [String: [CDWorkModel]] = workModels
            .filter { $0.presentationID != nil }
            .grouped { $0.presentationID ?? "" }
        rebuildBlockingCache(
            lessonAssignments: lessonAssignments,
            workModels: workModels,
            openWorkByPresentationID: openWorkByPresentationID
        )
        await Task.yield()
        if Task.isCancelled { return }

        calculateDaysSinceLastLesson(
            lessonAssignments: lessonAssignments, lessons: lessons, students: visibleStudents
        )
        await Task.yield()
        if Task.isCancelled { return }

        let (ready, blocked) = partitionIntoReadyAndBlocked(
            lessonAssignments: lessonAssignments,
            lessons: lessons,
            workModels: workModels,
            inboxOrderRaw: inboxOrderRaw,
            missWindow: missWindow
        )
        self.readyLessons = ready
        self.blockedLessons = blocked
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

    private func fetchLessonsData(from viewContext: NSManagedObjectContext) -> [CDLesson] {
        #if DEBUG
        return PerformanceLogger.measure(
            screenName: "PresentationsViewModel - Fetch Lessons",
            operation: { viewContext.safeFetch(CDFetchRequest(CDLesson.self)) }
        )
        #else
        return viewContext.safeFetch(CDFetchRequest(CDLesson.self))
        #endif
    }

    private func fetchStudentsData(from viewContext: NSManagedObjectContext) -> [CDStudent] {
        #if DEBUG
        return PerformanceLogger.measure(
            screenName: "PresentationsViewModel - Fetch Students",
            operation: { viewContext.safeFetch(CDFetchRequest(CDStudent.self)) }
        )
        #else
        return viewContext.safeFetch(CDFetchRequest(CDStudent.self))
        #endif
    }

    private func partitionIntoReadyAndBlocked(
        lessonAssignments: [CDLessonAssignment],
        lessons: [CDLesson],
        workModels: [CDWorkModel],
        inboxOrderRaw: String,
        missWindow: PresentationsMissWindow
    ) -> (ready: [CDLessonAssignment], blocked: [CDLessonAssignment]) {
        let allUnscheduled = lessonAssignments.filter { $0.scheduledFor == nil && !$0.isGiven }
        let blockingResults = BlockingAlgorithmEngine.checkBlocking(
            forBatch: allUnscheduled,
            lessons: lessons,
            allLessonAssignments: lessonAssignments,
            workModels: workModels
        )
        var ready: [CDLessonAssignment] = []
        var blocked: [CDLessonAssignment] = []
        for la in allUnscheduled {
            let result = la.id.flatMap { blockingResults[$0] }
                ?? BlockingAlgorithmEngine.BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
            if result.isBlocked { blocked.append(la) } else { ready.append(la) }
        }
        var ordered = InboxOrderStore.orderedUnscheduled(from: ready, orderRaw: inboxOrderRaw)
        ordered = ordered.filter { la in
            guard let threshold = missWindow.threshold else { return true }
            return la.resolvedStudentIDs.contains { sid in
                (daysSinceLastLessonByStudent[sid] ?? Int.max) >= threshold
            }
        }
        blocked.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        return (ordered, blocked)
    }

    // MARK: - Private Helpers — Blocking Cache

    private func rebuildBlockingCache(
        lessonAssignments: [CDLessonAssignment],
        workModels: [CDWorkModel],
        openWorkByPresentationID: [String: [CDWorkModel]]
    ) {
        blockingWorkCache = BlockingCacheBuilder.buildCache(
            lessonAssignments: lessonAssignments,
            lessons: cachedLessons,
            workModels: workModels,
            openWorkByPresentationID: openWorkByPresentationID
        )
    }

}

// MARK: - Cache Query Helpers

extension PresentationsViewModel {
    /// Get blocking work for a specific CDLessonAssignment (from cache)
    func getBlockingWork(_ la: CDLessonAssignment) -> [UUID: CDWorkModel] {
        guard let laID = la.id else { return [:] }
        return blockingWorkCache[laID] ?? [:]
    }

    /// Check if a lesson is blocked (from cache)
    func isBlocked(_ la: CDLessonAssignment) -> Bool {
        return !getBlockingWork(la).isEmpty
    }

    /// Get the earliest date with a scheduled lesson (computed from cached data)
    func earliestDateWithLesson(calendar: Calendar) -> Date? {
        let scheduledDates = cachedLessonAssignments.compactMap { la -> Date? in
            guard let scheduled = la.scheduledFor, !la.isGiven else { return nil }
            return calendar.startOfDay(for: scheduled)
        }
        return scheduledDates.min()
    }
}
