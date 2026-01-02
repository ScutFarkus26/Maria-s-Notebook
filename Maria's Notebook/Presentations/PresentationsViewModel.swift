// PresentationsViewModel.swift
// ViewModel to cache expensive blocking logic and optimize PresentationsView performance
// Preserves all existing functionality while improving responsiveness

import Foundation
import SwiftData
import SwiftUI
import Combine
#if DEBUG
#endif

@MainActor
final class PresentationsViewModel: ObservableObject {
    // MARK: - Published State
    @Published var readyLessons: [StudentLesson] = []
    @Published var blockedLessons: [StudentLesson] = []
    @Published var blockingContractsCache: [UUID: [UUID: WorkContract]] = [:]
    @Published var daysSinceLastLessonByStudent: [UUID: Int] = [:]
    
    // Expose cached students for use in filteredSnapshot (avoids redundant fetching)
    var cachedStudents: [Student] {
        self._cachedStudents
    }
    
    // MARK: - Dependencies (passed in update method)
    private var modelContext: ModelContext?
    private var calendar: Calendar = .current
    
    // MARK: - Cache State
    private var lastUpdateDate: Date?
    private var cachedLessons: [Lesson] = []
    private var cachedContracts: [WorkContract] = []
    private var cachedStudentLessons: [StudentLesson] = []
    private var _cachedStudents: [Student] = []
    private var lastStudentLessonsIDs: Set<UUID> = []
    private var lastLessonsIDs: Set<UUID> = []
    private var lastContractsIDs: Set<UUID> = []
    private var lastStudentsIDs: Set<UUID> = []
    
    // MARK: - Initialization
    init() {
        // Context and calendar will be set via update method
    }
    
    // MARK: - Public API
    
    /// Fetch data and update the view model. This replaces passing arrays from the view.
    /// The ViewModel now does targeted fetching internally instead of loading all data via @Query.
    func update(
        modelContext: ModelContext,
        calendar: Calendar,
        inboxOrderRaw: String,
        missWindow: PresentationsMissWindow,
        showTestStudents: Bool,
        testStudentNamesRaw: String
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        
        // Fetch data using targeted queries (only what we need)
        // 
        // ALGORITHMIC REQUIREMENT: The blocking logic and days-since-last-lesson calculations
        // require ALL records because:
        // 1. Blocking logic: To determine if a lesson is blocked, we need to build the complete
        //    lesson group structure (subject/group) and find the previous lesson in sequence.
        //    This requires all lessons to correctly identify the sequence order.
        // 2. Days since last lesson: To calculate days since the last lesson for each student,
        //    we need to examine ALL studentLessons to find the most recent one for each student.
        //    This cannot be optimized without changing the algorithm semantics.
        //
        // 1. Fetch all StudentLessons (needed for blocking logic and days-since calculations)
        let studentLessons: [StudentLesson] = {
            #if DEBUG
            return PerformanceLogger.measure(
                screenName: "PresentationsViewModel - Fetch StudentLessons",
                operation: {
                    modelContext.safeFetch(FetchDescriptor<StudentLesson>())
                }
            )
            #else
            return modelContext.safeFetch(FetchDescriptor<StudentLesson>())
            #endif
        }()
        
        // 2. Fetch all Lessons (needed for grouping and blocking logic - requires full group structure)
        let lessons: [Lesson] = {
            #if DEBUG
            return PerformanceLogger.measure(
                screenName: "PresentationsViewModel - Fetch Lessons",
                operation: {
                    modelContext.safeFetch(FetchDescriptor<Lesson>())
                }
            )
            #else
            return modelContext.safeFetch(FetchDescriptor<Lesson>())
            #endif
        }()
        
        // 3. Fetch all Students (needed for filtering and calculations)
        let students: [Student] = {
            #if DEBUG
            return PerformanceLogger.measure(
                screenName: "PresentationsViewModel - Fetch Students",
                operation: {
                    modelContext.safeFetch(FetchDescriptor<Student>())
                }
            )
            #else
            return modelContext.safeFetch(FetchDescriptor<Student>())
            #endif
        }()
        
        #if DEBUG
        PerformanceLogger.log(
            screenName: "PresentationsViewModel - Fetch Results",
            itemCount: studentLessons.count + lessons.count + students.count,
            duration: 0
        )
        PerformanceLogger.logScreenLoad(
            screenName: "PresentationsViewModel",
            itemCounts: [
                "studentLessons": studentLessons.count,
                "lessons": lessons.count,
                "students": students.count
            ]
        )
        #endif
        
        // 4. Fetch only active/review contracts (already optimized)
        let contracts: [WorkContract] = {
            #if DEBUG
            let startTime = Date()
            #endif
            let activeDesc = FetchDescriptor<WorkContract>(
                predicate: #Predicate { $0.statusRaw == "active" }
            )
            let reviewDesc = FetchDescriptor<WorkContract>(
                predicate: #Predicate { $0.statusRaw == "review" }
            )
            let active = modelContext.safeFetch(activeDesc)
            let review = modelContext.safeFetch(reviewDesc)
            let result = active + review
            #if DEBUG
            let duration = Date().timeIntervalSince(startTime)
            PerformanceLogger.log(
                screenName: "PresentationsViewModel - Fetch Contracts",
                itemCount: result.count,
                duration: duration
            )
            #endif
            return result
        }()
        
        // Check if data actually changed
        let studentLessonsIDs = Set(studentLessons.map { $0.id })
        let lessonsIDs = Set(lessons.map { $0.id })
        let contractsIDs = Set(contracts.map { $0.id })
        let studentsIDs = Set(students.map { $0.id })
        
        let dataChanged = studentLessonsIDs != lastStudentLessonsIDs ||
                         lessonsIDs != lastLessonsIDs ||
                         contractsIDs != lastContractsIDs ||
                         studentsIDs != lastStudentsIDs
        
        if !dataChanged && lastUpdateDate != nil {
            return // No need to recalculate
        }
        
        lastStudentLessonsIDs = studentLessonsIDs
        lastLessonsIDs = lessonsIDs
        lastContractsIDs = contractsIDs
        lastStudentsIDs = studentsIDs
        
        cachedStudentLessons = studentLessons
        cachedLessons = lessons
        cachedContracts = contracts
        _cachedStudents = students
        lastUpdateDate = Date()
        
        // Filter visible students
        let visibleStudents = TestStudentsFilter.filterVisible(students, show: showTestStudents, namesRaw: testStudentNamesRaw)
        
        // Build blocking contracts cache once
        rebuildBlockingCache(lessons: lessons, contracts: contracts)
        
        // Calculate days since last lesson
        calculateDaysSinceLastLesson(
            studentLessons: studentLessons,
            lessons: lessons,
            students: visibleStudents
        )
        
        // Filter unscheduled lessons
        let allUnscheduled = studentLessons.filter { $0.scheduledFor == nil && !$0.isGiven }
        
        // Separate blocked and ready lessons
        var ready: [StudentLesson] = []
        var blocked: [StudentLesson] = []
        
        for sl in allUnscheduled {
            if isBlocked(sl) {
                blocked.append(sl)
            } else {
                ready.append(sl)
            }
        }
        
        // Apply inbox ordering to ready lessons
        ready = InboxOrderStore.orderedUnscheduled(from: ready, orderRaw: inboxOrderRaw)
        
        // Filter by miss window
        ready = ready.filter { sl in
            guard let threshold = missWindow.threshold else { return true }
            for sid in sl.resolvedStudentIDs {
                let days = daysSinceLastLessonByStudent[sid] ?? Int.max
                if days >= threshold { return true }
            }
            return false
        }
        
        // Sort blocked lessons
        blocked.sort { $0.createdAt < $1.createdAt }
        
        self.readyLessons = ready
        self.blockedLessons = blocked
    }
    
    /// Get blocking contracts for a specific StudentLesson (from cache)
    func getBlockingContracts(_ sl: StudentLesson) -> [UUID: WorkContract] {
        return blockingContractsCache[sl.id] ?? [:]
    }
    
    /// Check if a lesson is blocked (from cache)
    func isBlocked(_ sl: StudentLesson) -> Bool {
        return !getBlockingContracts(sl).isEmpty
    }
    
    /// Get the earliest date with a scheduled lesson (computed from cached data)
    func earliestDateWithLesson(calendar: Calendar) -> Date? {
        let scheduledDates = cachedStudentLessons.compactMap { sl -> Date? in
            guard let scheduled = sl.scheduledFor, !sl.isGiven else { return nil }
            return calendar.startOfDay(for: scheduled)
        }
        return scheduledDates.min()
    }
    
    // MARK: - Private Helpers
    
    private func rebuildBlockingCache(lessons: [Lesson], contracts: [WorkContract]) {
        blockingContractsCache.removeAll()
        
        // Helper for fuzzy matching
        func norm(_ s: String) -> String {
            s.trimmed().lowercased()
        }
        
        // Group lessons by subject/group for efficient lookup
        var lessonsByGroup: [String: [Lesson]] = [:]
        for lesson in lessons {
            let key = "\(norm(lesson.subject))|\(norm(lesson.group))"
            lessonsByGroup[key, default: []].append(lesson)
        }
        
        // Sort each group
        for key in lessonsByGroup.keys {
            lessonsByGroup[key]?.sort { $0.orderInGroup < $1.orderInGroup }
        }
        
        // Build cache for all unscheduled student lessons
        let unscheduled = cachedStudentLessons.filter { $0.scheduledFor == nil && !$0.isGiven }
        
        for sl in unscheduled {
            guard let lessonIDUUID = UUID(uuidString: sl.lessonID),
                  let currentLesson = sl.lesson ?? lessons.first(where: { $0.id == lessonIDUUID }) else {
                continue
            }
            
            let subjectKey = norm(currentLesson.subject)
            let groupKey = norm(currentLesson.group)
            let groupKeyString = "\(subjectKey)|\(groupKey)"
            
            guard let groupLessons = lessonsByGroup[groupKeyString],
                  let currentIndex = groupLessons.firstIndex(where: { $0.id == currentLesson.id }),
                  currentIndex > 0 else {
                continue
            }
            
            let previousLesson = groupLessons[currentIndex - 1]
            var blocking: [UUID: WorkContract] = [:]
            
            for studentIDString in sl.studentIDs {
                guard let studentID = UUID(uuidString: studentIDString) else { continue }
                let pidString = previousLesson.id.uuidString
                
                if let contract = contracts.first(where: { c in
                    c.studentID == studentIDString &&
                    c.lessonID == pidString &&
                    (c.status == .active || c.status == .review)
                }) {
                    blocking[studentID] = contract
                }
            }
            
            if !blocking.isEmpty {
                blockingContractsCache[sl.id] = blocking
            }
        }
    }
    
    private func calculateDaysSinceLastLesson(
        studentLessons: [StudentLesson],
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
        
        let given = studentLessons.filter { 
            $0.isGiven && !excludedLessonIDs.contains($0.resolvedLessonID) 
        }
        
        var lastDateByStudent: [UUID: Date] = [:]
        for sl in given {
            let when = sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
            for sid in sl.resolvedStudentIDs {
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

