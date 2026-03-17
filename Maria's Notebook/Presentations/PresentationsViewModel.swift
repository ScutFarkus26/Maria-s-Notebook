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
    var lastSubjectByStudent: [UUID: String] = [:]
    var openWorkCountByStudent: [UUID: Int] = [:]

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

    // PERFORMANCE: Track pending update for cancellation
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

    // Fetch data and update the view model.
    // PERFORMANCE: Runs asynchronously in background to avoid blocking the main thread
    // swiftlint:disable:next function_parameter_count
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

    // Internal async implementation of update logic
    // swiftlint:disable:next function_parameter_count function_body_length
    private func updateAsync(
        modelContext: ModelContext,
        calendar: Calendar,
        inboxOrderRaw: String,
        missWindow: PresentationsMissWindow,
        showTestStudents: Bool,
        testStudentNamesRaw: String
    ) async {
        self.modelContext = modelContext
        self.calendar = calendar

        let lessonAssignments = fetchLessonAssignmentsData(from: modelContext)
        await Task.yield()
        if Task.isCancelled { return }

        let lessons = fetchLessonsData(from: modelContext)
        await Task.yield()
        if Task.isCancelled { return }

        let students = fetchStudentsData(from: modelContext)
        await Task.yield()
        if Task.isCancelled { return }

        let laHash = computeLessonAssignmentHash(lessonAssignments)
        let lHash = computeIDHash(lessons)
        let sHash = computeIDHash(students)
        let coreChanged = laHash != lastLessonAssignmentChangeHash
            || lHash != lastLessonsHash
            || sHash != lastStudentsHash
        if !coreChanged && lastUpdateDate != nil { return }

        let descriptor = FetchDescriptor<WorkModel>(
            predicate: #Predicate<WorkModel> { $0.statusRaw != "complete" }
        )
        let workModels = modelContext.safeFetch(descriptor)
        await Task.yield()
        if Task.isCancelled { return }

        lastLessonAssignmentChangeHash = laHash
        lastLessonsHash = lHash
        lastWorkModelHash = computeIDHash(workModels)
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
            students.filter { $0.isEnrolled }, show: showTestStudents, namesRaw: testStudentNamesRaw
        )
        cachedStudentsStorage = visibleStudents

        // Count open work items per student for suggest-next scoring
        var workCounts: [UUID: Int] = [:]
        for work in workModels {
            guard let sid = UUID(uuidString: work.studentID) else { continue }
            workCounts[sid, default: 0] += 1
        }
        self.openWorkCountByStudent = workCounts

        let openWorkByPresentationID: [String: [WorkModel]] = workModels
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

    private func fetchLessonAssignmentsData(from modelContext: ModelContext) -> [LessonAssignment] {
        #if DEBUG
        return PerformanceLogger.measure(
            screenName: "PresentationsViewModel - Fetch LessonAssignments",
            operation: { modelContext.safeFetch(FetchDescriptor<LessonAssignment>()) }
        )
        #else
        return modelContext.safeFetch(FetchDescriptor<LessonAssignment>())
        #endif
    }

    private func fetchLessonsData(from modelContext: ModelContext) -> [Lesson] {
        #if DEBUG
        return PerformanceLogger.measure(
            screenName: "PresentationsViewModel - Fetch Lessons",
            operation: { modelContext.safeFetch(FetchDescriptor<Lesson>()) }
        )
        #else
        return modelContext.safeFetch(FetchDescriptor<Lesson>())
        #endif
    }

    private func fetchStudentsData(from modelContext: ModelContext) -> [Student] {
        #if DEBUG
        return PerformanceLogger.measure(
            screenName: "PresentationsViewModel - Fetch Students",
            operation: { modelContext.safeFetch(FetchDescriptor<Student>()) }
        )
        #else
        return modelContext.safeFetch(FetchDescriptor<Student>())
        #endif
    }

    private func partitionIntoReadyAndBlocked(
        lessonAssignments: [LessonAssignment],
        lessons: [Lesson],
        workModels: [WorkModel],
        inboxOrderRaw: String,
        missWindow: PresentationsMissWindow
    ) -> (ready: [LessonAssignment], blocked: [LessonAssignment]) {
        let allUnscheduled = lessonAssignments.filter { $0.scheduledFor == nil && !$0.isGiven }
        let blockingResults = BlockingAlgorithmEngine.checkBlocking(
            forBatch: allUnscheduled,
            lessons: lessons,
            allLessonAssignments: lessonAssignments,
            workModels: workModels
        )
        var ready: [LessonAssignment] = []
        var blocked: [LessonAssignment] = []
        for la in allUnscheduled {
            let result = blockingResults[la.id]
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
        blocked.sort { $0.createdAt < $1.createdAt }
        return (ordered, blocked)
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

}

// MARK: - Days Since Last Lesson

extension PresentationsViewModel {
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

        let lessonsByID = Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let (lastDateByStudent, lastLessonIDByStudent) = buildLastLessonData(from: given)

        var subjects: [UUID: String] = [:]
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
            if let lessonID = lastLessonIDByStudent[s.id],
               let subject = lessonsByID[lessonID]?.subject,
               !subject.isEmpty {
                subjects[s.id] = subject
            }
        }

        self.daysSinceLastLessonByStudent = result
        self.lastSubjectByStudent = subjects
    }

    private func buildLastLessonData(
        from given: [LessonAssignment]
    ) -> (dateByStudent: [UUID: Date], lessonIDByStudent: [UUID: UUID]) {
        var lastDateByStudent: [UUID: Date] = [:]
        var lastLessonIDByStudent: [UUID: UUID] = [:]
        for la in given {
            let when = la.presentedAt ?? la.scheduledFor ?? la.createdAt
            for sid in la.resolvedStudentIDs {
                if let existing = lastDateByStudent[sid] {
                    if when > existing {
                        lastDateByStudent[sid] = when
                        lastLessonIDByStudent[sid] = la.resolvedLessonID
                    }
                } else {
                    lastDateByStudent[sid] = when
                    lastLessonIDByStudent[sid] = la.resolvedLessonID
                }
            }
        }
        return (lastDateByStudent, lastLessonIDByStudent)
    }
}
