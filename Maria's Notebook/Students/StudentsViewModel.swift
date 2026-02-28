import Foundation
import SwiftData

@Observable
@MainActor
final class StudentsViewModel {
    // MARK: - Cache State
    var cachedAttendanceRecords: [AttendanceRecord] = []
    var cachedLessonAssignments: [LessonAssignment] = []
    var cachedLessons: [UUID: Lesson] = [:]
    var cachedDaysSinceLastLesson: [UUID: Int] = [:]
    
    // MARK: - Change Detection
    private var lastAttendanceIDs: Set<UUID> = []
    private var lastLessonAssignmentIDs: Set<UUID> = []
    private var lastLessonIDs: Set<UUID> = []
    
    // MARK: - Filtering & Sorting
    func filteredStudents(
        modelContext: ModelContext,
        filter: StudentsFilter,
        sortOrder: SortOrder,
        searchString: String = "",
        today: Date = Date(),
        presentNowIDs: Set<UUID>? = nil,
        showTestStudents: Bool = true,
        testStudentNames: String = ""
    ) -> [Student] {
        // Build predicate for database-level filtering
        // Note: level filtering is done in-memory because levelRaw is private
        // Note: presentNow filtering is done in-memory because SwiftData #Predicate
        // doesn't support capturing local Set variables
        let predicate: Predicate<Student>? = nil
        
        // Build sort descriptors for database-level sorting where possible
        let sortDescriptors: [SortDescriptor<Student>] = {
            switch sortOrder {
            case .manual:
                return [SortDescriptor(\.manualOrder)]
            case .alphabetical:
                // Sort by firstName, then lastName, then manualOrder as tiebreaker
                return [
                    SortDescriptor(\.firstName),
                    SortDescriptor(\.lastName),
                    SortDescriptor(\.manualOrder)
                ]
            case .age:
                // Sort by birthday descending (younger first), then manualOrder
                return [
                    SortDescriptor(\.birthday, order: .reverse),
                    SortDescriptor(\.manualOrder)
                ]
            case .birthday, .lastLesson:
                // Complex sorts that require calculations - will sort in-memory
                // Use manualOrder as initial sort to maintain some order
                return [SortDescriptor(\.manualOrder)]
            }
        }()
        
        // Execute fetch with predicate and sort descriptors
        var descriptor = FetchDescriptor<Student>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortDescriptors
        
        var fetched = modelContext.safeFetch(descriptor)
        
        // PERFORMANCE: Combine all in-memory filters into a single pass to avoid creating intermediate arrays
        let query = searchString.trimmed().isEmpty ? nil : searchString.normalizedForComparison()
        let testFilter = TestStudentsFiltering.buildTestStudentFilter(showTestStudents: showTestStudents, testStudentNames: testStudentNames)
        
        fetched = fetched.filter { student in
            // 1. Level filtering (levelRaw is private, so can't be used in predicates)
            switch filter {
            case .all:
                break
            case .upper:
                if student.level != .upper { return false }
            case .lower:
                if student.level != .lower { return false }
            case .presentNow:
                if let ids = presentNowIDs, !ids.isEmpty {
                    if !ids.contains(student.id) { return false }
                } else {
                    return false // No IDs means no matches
                }
            }
            
            // 2. Test student filtering
            if !testFilter(student) { return false }
            
            // 3. Search string filtering
            if let query = query {
                let firstName = student.firstName.lowercased()
                let lastName = student.lastName.lowercased()
                let fullName = student.fullName.lowercased()
                if !firstName.contains(query) && !lastName.contains(query) && !fullName.contains(query) {
                    return false
                }
            }
            
            return true
        }
        
        // Apply in-memory sorting for complex sorts
        switch sortOrder {
        case .manual, .alphabetical, .age:
            // Already sorted by database, but may need refinement for alphabetical
            if sortOrder == .alphabetical {
                // Refine alphabetical sort using fullName for proper localized comparison
                return fetched.sorted { lhs, rhs in
                    let nameOrder = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName)
                    if nameOrder == .orderedSame {
                        return lhs.manualOrder < rhs.manualOrder
                    }
                    return nameOrder == .orderedAscending
                }
            }
            // For manual and age, database sort is sufficient (with manualOrder tiebreaker)
            return fetched
        case .birthday:
            // Sort by next birthday (requires calculation)
            let todayStart = Calendar.current.startOfDay(for: today)
            return fetched.sorted { (lhs: Student, rhs: Student) -> Bool in
                let l = nextBirthday(from: lhs.birthday, relativeTo: todayStart)
                let r = nextBirthday(from: rhs.birthday, relativeTo: todayStart)
                if l == r { return lhs.manualOrder < rhs.manualOrder }
                return l < r
            }
        case .lastLesson:
            // Last lesson sorting is done in StudentsView where presentation data is available
            return fetched
        }
    }

    func ensureInitialManualOrderIfNeeded(_ students: [Student]) -> Bool {
        let all = students
        guard !all.isEmpty else { return false }
        let allZero = all.allSatisfy { $0.manualOrder == 0 }
        if allZero {
            let sorted = all.sorted(by: StudentSortComparator.byFirstName)
            var changed = false
            for (idx, s) in sorted.enumerated() {
                if s.manualOrder != idx { s.manualOrder = idx; changed = true }
            }
            return changed
        }
        return false
    }

    func repairManualOrderUniquenessIfNeeded(_ students: [Student]) -> Bool {
        let all = students
        guard !all.isEmpty else { return false }
        var seen = Set<Int>()
        var duplicates: [Student] = []
        // Keep first occurrence of each order and collect duplicates (e.g., newly added with default 0)
        for s in all.sorted(by: { $0.manualOrder < $1.manualOrder }) {
            if seen.contains(s.manualOrder) {
                duplicates.append(s)
            } else {
                seen.insert(s.manualOrder)
            }
        }
        if !duplicates.isEmpty {
            var maxOrder = seen.max() ?? -1
            for s in duplicates {
                maxOrder += 1
                if s.manualOrder != maxOrder { s.manualOrder = maxOrder }
            }
            return true
        }
        return false
    }

    func mergeReorderedSubsetIntoAll(movingID: UUID, from fromIndex: Int, to toIndex: Int, current: [Student], allStudents: [Student]) -> [UUID] {
        // Full list ordered by current manualOrder
        let allOrdered = allStudents.sorted { $0.manualOrder < $1.manualOrder }

        // IDs of the currently visible (filtered) subset
        let subsetIDs = current.map { $0.id }
        var subset = subsetIDs
        // Reorder within the subset
        if let sFrom = subset.firstIndex(of: movingID) {
            let item = subset.remove(at: sFrom)
            let boundedIndex = max(0, min(subset.count, toIndex))
            subset.insert(item, at: boundedIndex)
        }

        // Merge: replace the positions of subset items in the full list with the new subset order
        let subsetSet = Set(subsetIDs)
        var subsetQueue = subset
        var newAllIDs: [UUID] = []
        for s in allOrdered {
            if subsetSet.contains(s.id) {
                // Take next from the reordered subset
                if !subsetQueue.isEmpty {
                    newAllIDs.append(subsetQueue.removeFirst())
                }
            } else {
                newAllIDs.append(s.id)
            }
        }
        return newAllIDs
    }

    // MARK: - Data Loading
    func loadDataOnDemand(
        mode: StudentMode,
        modelContext: ModelContext,
        calendar: Calendar,
        attendanceRecordIDs: Set<UUID>,
        presentationIDs: Set<UUID>,
        lessonIDs: Set<UUID>,
        students: [Student]
    ) {
        // Only load data for modes that need it
        guard mode == .roster || mode == .age || mode == .birthday || mode == .lastLesson else {
            return
        }
        
        // Check if data changed
        let dataChanged = attendanceRecordIDs != lastAttendanceIDs ||
                         presentationIDs != lastLessonAssignmentIDs ||
                         lessonIDs != lastLessonIDs
        
        guard dataChanged else { return }
        
        // Load today's attendance records for roster view
        if mode == .roster || mode == .age || mode == .birthday {
            let today = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            let descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate<AttendanceRecord> { record in
                    record.date >= today && record.date < tomorrow
                }
            )
            cachedAttendanceRecords = modelContext.safeFetch(descriptor)
        }
        
        // Load data for lastLesson mode
        if mode == .lastLesson {
            cachedDaysSinceLastLesson = computeDaysSinceLastLessonCache(
                for: students,
                using: modelContext,
                calendar: calendar
            )
        }
        
        // Update change tracking
        lastAttendanceIDs = attendanceRecordIDs
        lastLessonAssignmentIDs = presentationIDs
        lastLessonIDs = lessonIDs
    }
    
    // MARK: - Computed Helpers
    func presentNowIDs(from cachedRecords: [AttendanceRecord], calendar: Calendar) -> Set<UUID> {
        let today = calendar.startOfDay(for: Date())
        let filtered = cachedRecords.filter { 
            let recordDay = calendar.startOfDay(for: $0.date)
            return recordDay == today && $0.status == .present
        }
        return Set(filtered.compactMap { UUID(uuidString: $0.studentID) })
    }
    
    func hiddenTestStudentIDs(
        students: [Student],
        show: Bool,
        namesRaw: String
    ) -> Set<UUID> {
        guard !show else { return [] }
        
        let testNames = namesRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        
        guard !testNames.isEmpty else { return [] }
        
        return Set(students
            .filter { student in
                let firstName = student.firstName.lowercased()
                let lastName = student.lastName.lowercased()
                let fullName = student.fullName.lowercased()
                return testNames.contains(where: { testName in
                    firstName.contains(testName) || 
                    lastName.contains(testName) || 
                    fullName.contains(testName)
                })
            }
            .map { $0.id })
    }
    
    // MARK: - Helpers
    private func nextBirthday(from birthday: Date, relativeTo today: Date = Date()) -> Date {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: today)
        let comps = cal.dateComponents([.month, .day], from: birthday)
        guard let month = comps.month, let day = comps.day else { return .distantFuture }

        var year = cal.component(.year, from: todayStart)
        var thisYearComponents = DateComponents(year: year, month: month, day: day)
        var thisYearDate = cal.date(from: thisYearComponents)
        // Handle Feb 29 on non-leap years by using Feb 28
        if thisYearDate == nil && month == 2 && day == 29 {
            thisYearComponents.day = 28
            thisYearDate = cal.date(from: thisYearComponents)
        }
        guard let thisYear = thisYearDate else { return .distantFuture }

        if thisYear >= todayStart {
            return thisYear
        } else {
            year += 1
            var nextComponents = DateComponents(year: year, month: month, day: day)
            var nextDate = cal.date(from: nextComponents)
            if nextDate == nil && month == 2 && day == 29 {
                nextComponents.day = 28
                nextDate = cal.date(from: nextComponents)
            }
            return nextDate ?? thisYear
        }
    }

    /// Computes days since last lesson for multiple students efficiently.
    /// Fetches all lesson assignments once and filters in memory to avoid repeated queries.
    // MARK: - Shared Helper for Lesson Queries
    
    /// Shared data structure containing pre-fetched lesson data for efficient computation.
    private struct LessonQueryContext {
        let allLessonAssignments: [LessonAssignment]
        let excludedLessonIDs: Set<UUID>
        let calendar: Calendar
        let modelContext: ModelContext

        init(modelContext: ModelContext, calendar: Calendar) {
            self.calendar = calendar
            self.modelContext = modelContext

            // PERFORMANCE: Limit query to recent lessons (1 year) to avoid loading entire history
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date().addingTimeInterval(-365*24*3600)

            let descriptor = FetchDescriptor<LessonAssignment>(
                predicate: #Predicate { la in
                    la.createdAt >= oneYearAgo
                },
                sortBy: [
                    SortDescriptor(\LessonAssignment.presentedAt, order: .reverse),
                    SortDescriptor(\LessonAssignment.scheduledFor, order: .reverse),
                    SortDescriptor(\LessonAssignment.createdAt, order: .reverse)
                ]
            )
            self.allLessonAssignments = modelContext.safeFetch(descriptor)

            // Fetch lessons to exclude (parsha lessons) - cache this as Set for O(1) lookup
            let lessonsDescriptor = FetchDescriptor<Lesson>()
            let allLessons = modelContext.safeFetch(lessonsDescriptor)
            func norm(_ s: String) -> String { s.normalizedForComparison() }
            let ids = allLessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map { $0.id }
            self.excludedLessonIDs = Set(ids)
        }

        /// Returns all presented, non-excluded lesson assignments
        func presentedLessons() -> [LessonAssignment] {
            allLessonAssignments.filter {
                $0.isPresented && !excludedLessonIDs.contains($0.resolvedLessonID)
            }
        }
    }
    
    private func computeDaysSinceLastLessonCache(
        for students: [Student],
        using modelContext: ModelContext,
        calendar: Calendar
    ) -> [UUID: Int] {
        // Build shared query context once
        let context = LessonQueryContext(modelContext: modelContext, calendar: calendar)
        let presented = context.presentedLessons()

        // Build a map of student ID to most recent lesson date
        var lastDateByStudent: [UUID: Date] = [:]
        for sl in presented {
            let when = sl.presentedAt ?? sl.scheduledFor ?? sl.createdAt
            for sid in sl.resolvedStudentIDs {
                // Update if this is the first date or a more recent date
                if let existing = lastDateByStudent[sid] {
                    if when > existing {
                        lastDateByStudent[sid] = when
                    }
                } else {
                    lastDateByStudent[sid] = when
                }
            }
        }
        
        // Compute days since last lesson for each student
        var result: [UUID: Int] = [:]
        for student in students {
            if let lastDate = lastDateByStudent[student.id] {
                // Use LessonAgeHelper to compute school days since last lesson
                result[student.id] = LessonAgeHelper.schoolDaysSinceCreation(
                    createdAt: lastDate,
                    asOf: Date(),
                    using: modelContext,
                    calendar: calendar
                )
            } else {
                // No lesson found - return -1 to indicate no lesson
                result[student.id] = -1
            }
        }
        
        return result
    }
    
    /// Computes days since last lesson for a single student.
    /// This is a convenience method that queries SwiftData directly.
    /// For multiple students, use computeDaysSinceLastLessonCache instead.
    func daysSinceLastLesson(
        for student: Student,
        using modelContext: ModelContext,
        calendar: Calendar = .current
    ) -> Int {
        // Reuse the shared logic by calling the batch method with a single student
        let result = computeDaysSinceLastLessonCache(
            for: [student],
            using: modelContext,
            calendar: calendar
        )
        return result[student.id] ?? -1
    }
}

