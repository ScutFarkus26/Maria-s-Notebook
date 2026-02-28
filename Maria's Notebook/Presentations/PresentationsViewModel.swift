// PresentationsViewModel.swift
// ViewModel to cache expensive blocking logic and optimize PresentationsView performance
// Preserves all existing functionality while improving responsiveness

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class PresentationsViewModel {
    // MARK: - State
    var readyLessons: [LessonAssignment] = []
    var blockedLessons: [LessonAssignment] = []
    var blockingWorkCache: [UUID: [UUID: WorkModel]] = [:]
    var daysSinceLastLessonByStudent: [UUID: Int] = [:]

    // Expose cached students for use in filteredSnapshot (avoids redundant fetching)
    var cachedStudents: [Student] {
        self.cachedStudentsStorage
    }

    // Expose cached lessons for inbox filtering (avoids redundant fetching)
    var lessons: [Lesson] {
        self.cachedLessons
    }

    // MARK: - Dependencies
    private var modelContext: ModelContext?
    private var calendar: Calendar = .current

    // MARK: - Cache State
    private var lastUpdateDate: Date?
    private var cachedLessons: [Lesson] = []
    private var cachedWorkModels: [WorkModel] = []
    private var cachedLessonAssignments: [LessonAssignment] = []
    private var cachedStudentsStorage: [Student] = []

    // PERFORMANCE: Track loading state to prevent redundant concurrent updates
    private var isLoading = false
    private var pendingUpdateTask: Task<Void, Never>?

    // PERFORMANCE: Use hash-based change detection
    private var lastLessonAssignmentChangeHash: Int?
    private var lastLessonsHash: Int?
    private var lastWorkModelHash: Int?
    private var lastStudentsHash: Int?

    // MARK: - Initialization
    init() {}

    // MARK: - Change Detection Helpers

    /// Computes a hash for LessonAssignment change detection
    private func computeLessonAssignmentHash(_ assignments: [LessonAssignment]) -> Int {
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
    private func computeIDHash<T: Identifiable>(_ items: [T]) -> Int where T.ID == UUID {
        var hasher = Hasher()
        for item in items {
            hasher.combine(item.id)
        }
        return hasher.finalize()
    }

    // MARK: - Public API

    /// Fetch data and update the view model.
    /// PERFORMANCE: Runs asynchronously in background to avoid blocking the main thread
    func update(
        modelContext: ModelContext,
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
                modelContext: modelContext,
                calendar: calendar,
                inboxOrderRaw: inboxOrderRaw,
                missWindow: missWindow,
                showTestStudents: showTestStudents,
                testStudentNamesRaw: testStudentNamesRaw
            )
        }
    }

    /// Internal async implementation of update logic
    private func updateAsync(
        modelContext: ModelContext,
        calendar: Calendar,
        inboxOrderRaw: String,
        missWindow: PresentationsMissWindow,
        showTestStudents: Bool,
        testStudentNamesRaw: String
    ) async {
        // Prevent redundant concurrent updates
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        self.modelContext = modelContext
        self.calendar = calendar

        // 1. Fetch all LessonAssignments
        let lessonAssignments: [LessonAssignment]
        #if DEBUG
        lessonAssignments = PerformanceLogger.measure(
            screenName: "PresentationsViewModel - Fetch LessonAssignments",
            operation: {
                modelContext.safeFetch(FetchDescriptor<LessonAssignment>())
            }
        )
        #else
        lessonAssignments = modelContext.safeFetch(FetchDescriptor<LessonAssignment>())
        #endif

        await Task.yield()
        if Task.isCancelled { return }

        // 2. Fetch all Lessons
        let lessons: [Lesson]
        #if DEBUG
        lessons = PerformanceLogger.measure(
            screenName: "PresentationsViewModel - Fetch Lessons",
            operation: {
                modelContext.safeFetch(FetchDescriptor<Lesson>())
            }
        )
        #else
        lessons = modelContext.safeFetch(FetchDescriptor<Lesson>())
        #endif

        await Task.yield()
        if Task.isCancelled { return }

        // 3. Fetch all Students
        let students: [Student]
        #if DEBUG
        students = PerformanceLogger.measure(
            screenName: "PresentationsViewModel - Fetch Students",
            operation: {
                modelContext.safeFetch(FetchDescriptor<Student>())
            }
        )
        #else
        students = modelContext.safeFetch(FetchDescriptor<Student>())
        #endif

        await Task.yield()
        if Task.isCancelled { return }

        // PERFORMANCE: Hash-based change detection
        let lessonAssignmentHash = computeLessonAssignmentHash(lessonAssignments)
        let lessonsHash = computeIDHash(lessons)
        let studentsHash = computeIDHash(students)

        let coreDataChanged = lessonAssignmentHash != lastLessonAssignmentChangeHash ||
                             lessonsHash != lastLessonsHash ||
                             studentsHash != lastStudentsHash

        if !coreDataChanged && lastUpdateDate != nil {
            return
        }

        // 4. Fetch non-complete WorkModels
        let workModels: [WorkModel] = {
            let descriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate<WorkModel> { $0.statusRaw != "complete" }
            )
            return modelContext.safeFetch(descriptor)
        }()

        await Task.yield()
        if Task.isCancelled { return }

        let workModelHash = computeIDHash(workModels)

        // Update change tracking
        lastLessonAssignmentChangeHash = lessonAssignmentHash
        lastLessonsHash = lessonsHash
        lastWorkModelHash = workModelHash
        lastStudentsHash = studentsHash

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

        // Filter visible students
        let visibleStudents = TestStudentsFilter.filterVisible(students, show: showTestStudents, namesRaw: testStudentNamesRaw)
        cachedStudentsStorage = visibleStudents

        // Build openWorkByPresentationID dictionary
        let openWorkByPresentationID: [String: [WorkModel]] = workModels
            .filter { $0.presentationID != nil }
            .grouped { $0.presentationID ?? "" }

        // Build blocking work cache
        rebuildBlockingCache(
            lessonAssignments: lessonAssignments,
            workModels: workModels,
            openWorkByPresentationID: openWorkByPresentationID
        )

        await Task.yield()
        if Task.isCancelled { return }

        // Calculate days since last lesson
        calculateDaysSinceLastLesson(
            lessonAssignments: lessonAssignments,
            lessons: lessons,
            students: visibleStudents
        )

        await Task.yield()
        if Task.isCancelled { return }

        // Filter unscheduled, non-presented assignments (inbox items)
        let allUnscheduled = lessonAssignments.filter { $0.scheduledFor == nil && !$0.isGiven }

        // Separate blocked and ready using prerequisite blocking logic
        var ready: [LessonAssignment] = []
        var blocked: [LessonAssignment] = []

        let blockingResults = BlockingAlgorithmEngine.checkBlocking(
            forBatch: allUnscheduled,
            lessons: lessons,
            allLessonAssignments: lessonAssignments,
            workModels: workModels
        )

        for la in allUnscheduled {
            let result = blockingResults[la.id] ?? BlockingAlgorithmEngine.BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
            if result.isBlocked {
                blocked.append(la)
            } else {
                ready.append(la)
            }
        }

        // Apply inbox ordering
        ready = InboxOrderStore.orderedUnscheduled(from: ready, orderRaw: inboxOrderRaw)

        // Filter by miss window
        ready = ready.filter { la in
            guard let threshold = missWindow.threshold else { return true }
            for sid in la.resolvedStudentIDs {
                let days = daysSinceLastLessonByStudent[sid] ?? Int.max
                if days >= threshold { return true }
            }
            return false
        }

        // Sort blocked
        blocked.sort { $0.createdAt < $1.createdAt }

        self.readyLessons = ready
        self.blockedLessons = blocked
    }

    /// Get blocking work for a specific LessonAssignment (from cache)
    func getBlockingWork(_ la: LessonAssignment) -> [UUID: WorkModel] {
        return blockingWorkCache[la.id] ?? [:]
    }

    /// Check if a lesson is blocked (from cache)
    func isBlocked(_ la: LessonAssignment) -> Bool {
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

    // MARK: - Private Helpers

    private func rebuildBlockingCache(
        lessonAssignments: [LessonAssignment],
        workModels: [WorkModel],
        openWorkByPresentationID: [String: [WorkModel]]
    ) {
        blockingWorkCache = BlockingCacheBuilder.buildCache(
            lessonAssignments: lessonAssignments,
            lessons: cachedLessons,
            workModels: workModels,
            openWorkByPresentationID: openWorkByPresentationID
        )
    }

    private func calculateDaysSinceLastLesson(
        lessonAssignments: [LessonAssignment],
        lessons: [Lesson],
        students: [Student]
    ) {
        var result: [UUID: Int] = [:]

        func norm(_ s: String) -> String {
            s.trimmed().lowercased()
        }

        let excludedLessonIDs: Set<UUID> = {
            let ids = lessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map { $0.id }
            return Set(ids)
        }()

        let given = lessonAssignments.filter {
            $0.isGiven && !excludedLessonIDs.contains($0.resolvedLessonID)
        }

        var lastDateByStudent: [UUID: Date] = [:]
        for la in given {
            let when = la.presentedAt ?? la.scheduledFor ?? la.createdAt
            for sid in la.resolvedStudentIDs {
                if let existing = lastDateByStudent[sid] {
                    if when > existing { lastDateByStudent[sid] = when }
                } else {
                    lastDateByStudent[sid] = when
                }
            }
        }

        for s in students {
            if let last = lastDateByStudent[s.id] {
                guard let modelContext = modelContext else { continue }
                let days = LessonAgeHelper.schoolDaysSinceCreation(
                    createdAt: last,
                    asOf: Date(),
                    using: modelContext,
                    calendar: calendar
                )
                result[s.id] = days
            } else {
                result[s.id] = Int.max
            }
        }

        self.daysSinceLastLessonByStudent = result
    }
}
