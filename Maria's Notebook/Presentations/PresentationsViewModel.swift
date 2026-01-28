// PresentationsViewModel.swift
// ViewModel to cache expensive blocking logic and optimize PresentationsView performance
// Preserves all existing functionality while improving responsiveness

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class PresentationsViewModel: ObservableObject {
    // MARK: - Published State
    @Published var readyLessons: [StudentLesson] = []
    @Published var blockedLessons: [StudentLesson] = []
    @Published var blockingWorkCache: [UUID: [UUID: WorkModel]] = [:]
    @Published var daysSinceLastLessonByStudent: [UUID: Int] = [:]
    
    // Expose cached students for use in filteredSnapshot (avoids redundant fetching)
    var cachedStudents: [Student] {
        self.cachedStudentsStorage
    }

    // Expose cached lessons for inbox filtering (avoids redundant fetching)
    var lessons: [Lesson] {
        self.cachedLessons
    }
    
    // MARK: - Dependencies (passed in update method)
    private var modelContext: ModelContext?
    private var calendar: Calendar = .current
    
    // MARK: - Cache State
    private var lastUpdateDate: Date?
    private var cachedLessons: [Lesson] = []
    private var cachedWorkModels: [WorkModel] = []
    private var cachedPresentations: [Presentation] = []
    private var cachedStudentLessons: [StudentLesson] = []
    private var cachedStudentsStorage: [Student] = []
    private var lastStudentLessonChangeKeys: Set<StudentLessonChangeKey> = []
    private var lastLessonsIDs: Set<UUID> = []
    private var lastWorkModelIDs: Set<UUID> = []
    private var lastStudentsIDs: Set<UUID> = []
    
    private struct StudentLessonChangeKey: Hashable {
        let id: UUID
        let scheduledFor: Double
        let givenAt: Double
        let isPresented: Bool
    }
    
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
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
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
        
        // Check if core data actually changed (before fetching WorkModels/Presentations)
        let studentLessonKeys = Set(studentLessons.map {
            StudentLessonChangeKey(
                id: $0.id,
                scheduledFor: $0.scheduledFor?.timeIntervalSinceReferenceDate ?? -1,
                givenAt: $0.givenAt?.timeIntervalSinceReferenceDate ?? -1,
                isPresented: $0.isPresented
            )
        })
        let lessonsIDs = Set(lessons.map { $0.id })
        let studentsIDs = Set(students.map { $0.id })

        // Early return if no changes to avoid redundant fetches and processing
        let coreDataChanged = studentLessonKeys != lastStudentLessonChangeKeys ||
                             lessonsIDs != lastLessonsIDs ||
                             studentsIDs != lastStudentsIDs

        if !coreDataChanged && lastUpdateDate != nil {
            return // No need to recalculate
        }

        // 4. Fetch non-complete WorkModels (filter at database layer for efficiency)
        let workModels: [WorkModel] = {
            let descriptor = FetchDescriptor<WorkModel>(
                predicate: #Predicate<WorkModel> { $0.statusRaw != "complete" }
            )
            return modelContext.safeFetch(descriptor)
        }()

        // 5. Fetch all Presentations (needed to find presentation for each StudentLesson)
        let presentations: [Presentation] = modelContext.safeFetch(FetchDescriptor<Presentation>())

        // Track WorkModel IDs for future change detection
        let workModelIDs = Set(workModels.map { $0.id })

        // Update change tracking state
        lastStudentLessonChangeKeys = studentLessonKeys
        lastLessonsIDs = lessonsIDs
        lastWorkModelIDs = workModelIDs
        lastStudentsIDs = studentsIDs

        #if DEBUG
        // Only log when we're actually processing changes
        PerformanceLogger.logScreenLoad(
            screenName: "PresentationsViewModel",
            itemCounts: [
                "studentLessons": studentLessons.count,
                "lessons": lessons.count,
                "students": students.count,
                "workModels": workModels.count,
                "presentations": presentations.count
            ]
        )
        #endif
        
        cachedStudentLessons = studentLessons
        cachedLessons = lessons
        cachedWorkModels = workModels
        cachedPresentations = presentations
        cachedStudentsStorage = students
        lastUpdateDate = Date()
        
        // Filter visible students
        let visibleStudents = TestStudentsFilter.filterVisible(students, show: showTestStudents, namesRaw: testStudentNamesRaw)
        
        // Build openWorkByPresentationID dictionary for fast lookup
        // Group open WorkModels by presentationID (where presentationID != nil)
        let openWorkByPresentationID: [String: [WorkModel]] = {
            Dictionary(grouping: workModels.filter { $0.presentationID != nil }) { work in
                work.presentationID ?? ""
            }
        }()
        
        // Build a map of presentations by legacyStudentLessonID for efficient lookup
        var presentationsByLegacyID: [String: Presentation] = [:]
        for presentation in presentations {
            if let legacyID = presentation.legacyStudentLessonID {
                presentationsByLegacyID[legacyID] = presentation
            }
        }
        
        // Build blocking work cache once (still needed for getBlockingWork)
        rebuildBlockingCache(workModels: workModels, presentations: presentations, presentationsByLegacyID: presentationsByLegacyID, openWorkByPresentationID: openWorkByPresentationID)
        
        // Calculate days since last lesson
        calculateDaysSinceLastLesson(
            studentLessons: studentLessons,
            lessons: lessons,
            students: visibleStudents
        )
        
        // Filter unscheduled lessons
        let allUnscheduled = studentLessons.filter { $0.scheduledFor == nil && !$0.isGiven }
        
        // Separate blocked and ready lessons using prerequisite blocking logic
        var ready: [StudentLesson] = []
        var blocked: [StudentLesson] = []

        for sl in allUnscheduled {
            let result = BlockingAlgorithmEngine.checkBlocking(
                for: sl,
                lessons: lessons,
                studentLessons: studentLessons,
                presentations: presentations,
                workModels: workModels
            )

            if result.isBlocked {
                blocked.append(sl)
            } else {
                ready.append(sl)
            }
        }
        
        // Filter presented items for Inbox: presented (givenAt != nil or isPresented == true) AND has open work
        let presentedLessons = studentLessons.filter { $0.isGiven }
        var inboxItems: [StudentLesson] = []
        
        for sl in presentedLessons {
            let legacyID = sl.id.uuidString
            let presentation = presentationsByLegacyID[legacyID]
            let presentationIDString = presentation?.id.uuidString
            
            // Inbox: presented AND has open work
            if let pid = presentationIDString, let openWork = openWorkByPresentationID[pid], !openWork.isEmpty {
                inboxItems.append(sl)
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
    
    /// Get blocking work for a specific StudentLesson (from cache)
    func getBlockingWork(_ sl: StudentLesson) -> [UUID: WorkModel] {
        return blockingWorkCache[sl.id] ?? [:]
    }

    /// Check if a lesson is blocked (from cache)
    func isBlocked(_ sl: StudentLesson) -> Bool {
        return !getBlockingWork(sl).isEmpty
    }
    
    /// Get the earliest date with a scheduled lesson (computed from cached data)
    func earliestDateWithLesson(calendar: Calendar) -> Date? {
        let scheduledDates = cachedStudentLessons.compactMap { sl -> Date? in
            guard let scheduled = sl.scheduledFor, !sl.isGiven else { return nil }
            return calendar.startOfDay(for: scheduled)
        }
        return scheduledDates.min()
    }
    
    // MARK: - Private Helpers (delegated to BlockingAlgorithmEngine and BlockingCacheBuilder)

    private func rebuildBlockingCache(workModels: [WorkModel], presentations: [Presentation], presentationsByLegacyID: [String: Presentation], openWorkByPresentationID: [String: [WorkModel]]) {
        // Use BlockingCacheBuilder to construct the cache
        blockingWorkCache = BlockingCacheBuilder.buildCache(
            studentLessons: cachedStudentLessons,
            lessons: cachedLessons,
            workModels: workModels,
            presentations: presentations,
            presentationsByLegacyID: presentationsByLegacyID,
            openWorkByPresentationID: openWorkByPresentationID
        )
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

