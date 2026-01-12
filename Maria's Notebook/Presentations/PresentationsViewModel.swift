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
    @Published var blockingContractsCache: [UUID: [UUID: WorkModel]] = [:]
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
    private var cachedWorkModels: [WorkModel] = []
    private var cachedPresentations: [Presentation] = []
    private var cachedStudentLessons: [StudentLesson] = []
    private var _cachedStudents: [Student] = []
    private var lastStudentLessonsIDs: Set<UUID> = []
    private var lastLessonsIDs: Set<UUID> = []
    private var lastWorkModelIDs: Set<UUID> = []
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
        
        // 4. Fetch all WorkModels (we'll filter in memory to avoid predicate issues)
        // Prefer broad fetch and filter in memory per constraints
        let workModels: [WorkModel] = {
            #if DEBUG
            let startTime = Date()
            #endif
            let allWork = modelContext.safeFetch(FetchDescriptor<WorkModel>())
            // Filter for non-complete work only (active and review status)
            let result = allWork.filter { $0.statusRaw != "complete" }
            #if DEBUG
            let duration = Date().timeIntervalSince(startTime)
            PerformanceLogger.log(
                screenName: "PresentationsViewModel - Fetch WorkModels",
                itemCount: result.count,
                duration: duration
            )
            #endif
            return result
        }()
        
        // 5. Fetch all Presentations (needed to find presentation for each StudentLesson)
        let presentations: [Presentation] = {
            #if DEBUG
            let startTime = Date()
            #endif
            let result = modelContext.safeFetch(FetchDescriptor<Presentation>())
            #if DEBUG
            let duration = Date().timeIntervalSince(startTime)
            PerformanceLogger.log(
                screenName: "PresentationsViewModel - Fetch Presentations",
                itemCount: result.count,
                duration: duration
            )
            #endif
            return result
        }()
        
        // Check if data actually changed
        let studentLessonsIDs = Set(studentLessons.map { $0.id })
        let lessonsIDs = Set(lessons.map { $0.id })
        let workModelIDs = Set(workModels.map { $0.id })
        let studentsIDs = Set(students.map { $0.id })
        
        let dataChanged = studentLessonsIDs != lastStudentLessonsIDs ||
                         lessonsIDs != lastLessonsIDs ||
                         workModelIDs != lastWorkModelIDs ||
                         studentsIDs != lastStudentsIDs
        
        if !dataChanged && lastUpdateDate != nil {
            return // No need to recalculate
        }
        
        lastStudentLessonsIDs = studentLessonsIDs
        lastLessonsIDs = lessonsIDs
        lastWorkModelIDs = workModelIDs
        lastStudentsIDs = studentsIDs
        
        cachedStudentLessons = studentLessons
        cachedLessons = lessons
        cachedWorkModels = workModels
        cachedPresentations = presentations
        _cachedStudents = students
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
        
        // Build blocking work cache once (still needed for getBlockingContracts)
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
            let (isBlocked, prereqOpenCount) = checkBlockingForStudentLesson(
                sl: sl,
                lessons: lessons,
                studentLessons: studentLessons,
                presentations: presentations,
                workModels: workModels
            )
            
            // Add diagnostic print
            let groupKey = sl.studentGroupKeyPersisted.isEmpty ? sl.studentGroupKey : sl.studentGroupKeyPersisted
            print("BLOCKING DIAGNOSTIC: sl=\(sl.id) groupKey=\(groupKey) blocked=\(isBlocked) prereqOpenCount=\(prereqOpenCount)")
            
            if isBlocked {
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
        
        // TEMP debug prints (DEBUG only)
        #if DEBUG
        print("PresentationsView debug: openWorkModels=\(workModels.count)")
        print("PresentationsView debug: openWorkByPresentationID keys=\(openWorkByPresentationID.keys.count)")
        print("PresentationsView debug: inboxCount=\(inboxItems.count) onDeckCount=\(blocked.count)")
        #endif
        
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
    func getBlockingContracts(_ sl: StudentLesson) -> [UUID: WorkModel] {
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
    
    /// Check if a StudentLesson is blocked by incomplete prerequisite work from the preceding lesson
    private func checkBlockingForStudentLesson(
        sl: StudentLesson,
        lessons: [Lesson],
        studentLessons: [StudentLesson],
        presentations: [Presentation],
        workModels: [WorkModel]
    ) -> (isBlocked: Bool, prereqOpenCount: Int) {
        // Find the current lesson
        guard let currentLessonID = UUID(uuidString: sl.lessonID),
              let currentLesson = lessons.first(where: { $0.id == currentLessonID }) else {
            return (false, 0)
        }
        
        // Find the preceding lesson in the sequence (same subject/group, previous orderInGroup)
        let precedingLesson = findPrecedingLesson(
            currentLesson: currentLesson,
            lessons: lessons
        )
        
        guard let precedingLesson = precedingLesson else {
            // No preceding lesson means no prerequisites to check
            return (false, 0)
        }
        
        // Find the Presentation for the preceding lesson with the same student group
        _ = sl.studentGroupKeyPersisted.isEmpty ? sl.studentGroupKey : sl.studentGroupKeyPersisted
        let studentIDs = Set(sl.resolvedStudentIDs.map { $0.uuidString })
        
        let precedingPresentation = presentations.first { presentation in
            guard presentation.lessonID == precedingLesson.id.uuidString else { return false }
            let presentationStudentIDs = Set(presentation.studentIDs)
            return presentationStudentIDs == studentIDs
        }
        
        guard let precedingPresentation = precedingPresentation else {
            // No presentation for preceding lesson means no prerequisites
            return (false, 0)
        }
        
        // Find WorkModel records linked to the preceding presentation
        let precedingPresentationID = precedingPresentation.id.uuidString
        let prerequisiteWork = workModels.filter { work in
            work.presentationID == precedingPresentationID
        }
        
        // Check if ANY prerequisite work is incomplete for any required student
        var prereqOpenCount = 0
        var isBlocked = false
        
        for work in prerequisiteWork {
            if isWorkComplete(work: work, requiredStudentIDs: sl.resolvedStudentIDs) {
                continue // This work is complete
            }
            
            prereqOpenCount += 1
            
            // Check if this work blocks any required student
            if workHasIncompleteForRequiredStudents(work: work, requiredStudentIDs: sl.resolvedStudentIDs) {
                isBlocked = true
            }
        }
        
        return (isBlocked, prereqOpenCount)
    }
    
    /// Find the preceding lesson in the sequence (same subject/group, previous orderInGroup)
    private func findPrecedingLesson(currentLesson: Lesson, lessons: [Lesson]) -> Lesson? {
        let currentSubject = currentLesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = currentLesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else {
            return nil
        }
        
        // Find all lessons in the same subject/group
        let candidates = lessons.filter { lesson in
            lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            lesson.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }
        
        // Find the current lesson's index
        guard let currentIndex = candidates.firstIndex(where: { $0.id == currentLesson.id }),
              currentIndex > 0 else {
            return nil // No preceding lesson
        }
        
        return candidates[currentIndex - 1]
    }
    
    /// Check if work is complete (either statusRaw == "complete" OR all relevant WorkParticipantEntity entries have completedAt != nil)
    private func isWorkComplete(work: WorkModel, requiredStudentIDs: [UUID]) -> Bool {
        // Check if work status is complete
        if work.statusRaw == "complete" {
            return true
        }
        
        // Check if per-student completion: all relevant WorkParticipantEntity entries have completedAt != nil
        if let participants = work.participants, !participants.isEmpty {
            let requiredStudentIDStrings = Set(requiredStudentIDs.map { $0.uuidString })
            
            // Only check participants that are in the required student list (relevant participants)
            let relevantParticipants = participants.filter { participant in
                requiredStudentIDStrings.contains(participant.studentID)
            }
            
            // All relevant WorkParticipantEntity entries must have completedAt != nil
            // If there are no relevant participants, we can't check per-student completion, so fall back to status
            if relevantParticipants.isEmpty {
                return false // No relevant participants means not complete (status already checked)
            }
            
            return relevantParticipants.allSatisfy { $0.completedAt != nil }
        }
        
        // No participants means we check by status only (already checked above)
        return false
    }
    
    /// Check if work has incomplete status for any required student
    private func workHasIncompleteForRequiredStudents(work: WorkModel, requiredStudentIDs: [UUID]) -> Bool {
        // This is the inverse of isWorkComplete - if work is not complete, it has incomplete status
        return !isWorkComplete(work: work, requiredStudentIDs: requiredStudentIDs)
    }
    
    private func rebuildBlockingCache(workModels: [WorkModel], presentations: [Presentation], presentationsByLegacyID: [String: Presentation], openWorkByPresentationID: [String: [WorkModel]]) {
        blockingContractsCache.removeAll()
        
        // Build cache for all unscheduled student lessons using prerequisite blocking logic
        let unscheduled = cachedStudentLessons.filter { $0.scheduledFor == nil && !$0.isGiven }
        
        for sl in unscheduled {
            // Find the current lesson
            guard let currentLessonID = UUID(uuidString: sl.lessonID),
                  let currentLesson = cachedLessons.first(where: { $0.id == currentLessonID }) else {
                continue
            }
            
            // Find the preceding lesson in the sequence
            guard let precedingLesson = findPrecedingLesson(
                currentLesson: currentLesson,
                lessons: cachedLessons
            ) else {
                continue // No preceding lesson means no prerequisites
            }
            
            // Find the Presentation for the preceding lesson with the same student group
            let studentIDs = Set(sl.resolvedStudentIDs.map { $0.uuidString })
            guard let precedingPresentation = presentations.first(where: { presentation in
                guard presentation.lessonID == precedingLesson.id.uuidString else { return false }
                let presentationStudentIDs = Set(presentation.studentIDs)
                return presentationStudentIDs == studentIDs
            }) else {
                continue // No presentation for preceding lesson means no prerequisites
            }
            
            // Find incomplete prerequisite work linked to the preceding presentation
            let precedingPresentationID = precedingPresentation.id.uuidString
            let prerequisiteWork = workModels.filter { work in
                work.presentationID == precedingPresentationID &&
                !isWorkComplete(work: work, requiredStudentIDs: sl.resolvedStudentIDs)
            }
            
            // Build blocking dictionary: map student IDs to their blocking work
            var blocking: [UUID: WorkModel] = [:]
            for work in prerequisiteWork {
                // For work with participants, map to specific students
                if let participants = work.participants, !participants.isEmpty {
                    for participant in participants {
                        guard let studentID = UUID(uuidString: participant.studentID),
                              sl.resolvedStudentIDs.contains(studentID),
                              participant.completedAt == nil else {
                            continue
                        }
                        // Only add if not already added (first incomplete work per student)
                        if blocking[studentID] == nil {
                            blocking[studentID] = work
                        }
                    }
                } else {
                    // No participants: work blocks all students in the group
                    for studentID in sl.resolvedStudentIDs {
                        if blocking[studentID] == nil {
                            blocking[studentID] = work
                        }
                    }
                }
            }
            
            if !blocking.isEmpty {
                blockingContractsCache[sl.id] = blocking
            }
        }
        
        // Also build cache for presented lessons (for Inbox) - these still use current presentation work
        let presented = cachedStudentLessons.filter { $0.isGiven }
        for sl in presented {
            let legacyID = sl.id.uuidString
            guard let presentation = presentationsByLegacyID[legacyID] else {
                continue
            }
            
            let presentationIDString = presentation.id.uuidString
            
            // Get open work for this presentation from openWorkByPresentationID
            guard let openWork = openWorkByPresentationID[presentationIDString], !openWork.isEmpty else {
                continue
            }
            
            // Build blocking dictionary for all students with unresolved work
            var blocking: [UUID: WorkModel] = [:]
            for studentIDString in sl.studentIDs {
                guard let studentID = UUID(uuidString: studentIDString) else { continue }
                if let work = openWork.first(where: { w in
                    w.presentationID == presentationIDString &&
                    w.studentID == studentIDString &&
                    w.statusRaw != "complete"
                }) {
                    blocking[studentID] = work
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

