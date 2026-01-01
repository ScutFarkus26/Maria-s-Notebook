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
    @Published var blockingContractsCache: [UUID: [UUID: WorkContract]] = [:]
    @Published var daysSinceLastLessonByStudent: [UUID: Int] = [:]
    
    // MARK: - Dependencies (passed in update method)
    private var modelContext: ModelContext?
    private var calendar: Calendar = .current
    
    // MARK: - Cache State
    private var lastUpdateDate: Date?
    private var cachedLessons: [Lesson] = []
    private var cachedContracts: [WorkContract] = []
    private var cachedStudentLessons: [StudentLesson] = []
    private var cachedStudents: [Student] = []
    
    // MARK: - Initialization
    init() {
        // Context and calendar will be set via update method
    }
    
    // MARK: - Public API
    
    /// Update the view model with fresh data. Call this when data changes.
    func update(
        modelContext: ModelContext,
        calendar: Calendar,
        studentLessons: [StudentLesson],
        lessons: [Lesson],
        students: [Student],
        contracts: [WorkContract],
        inboxOrderRaw: String,
        missWindow: PresentationsMissWindow,
        showTestStudents: Bool,
        testStudentNamesRaw: String
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        // Only recalculate if data actually changed
        let dataChanged = cachedStudentLessons.count != studentLessons.count ||
                         cachedLessons.count != lessons.count ||
                         cachedContracts.count != contracts.count ||
                         cachedStudents.count != students.count
        
        if !dataChanged && lastUpdateDate != nil {
            // Check if contracts changed (most likely to change)
            let contractsChanged = Set(cachedContracts.map { $0.id }) != Set(contracts.map { $0.id })
            if !contractsChanged {
                return // No need to recalculate
            }
        }
        
        cachedStudentLessons = studentLessons
        cachedLessons = lessons
        cachedContracts = contracts
        cachedStudents = students
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
    
    // MARK: - Private Helpers
    
    private func rebuildBlockingCache(lessons: [Lesson], contracts: [WorkContract]) {
        blockingContractsCache.removeAll()
        
        // Helper for fuzzy matching
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
            guard let currentLesson = sl.lesson ?? lessons.first(where: { $0.id == sl.lessonID }) else {
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
            
            for studentID in sl.studentIDs {
                let sidString = studentID.uuidString
                let pidString = previousLesson.id.uuidString
                
                if let contract = contracts.first(where: { c in
                    c.studentID == sidString &&
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
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

