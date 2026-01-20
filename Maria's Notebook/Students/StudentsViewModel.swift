import Foundation
import SwiftData

struct StudentsViewModel {
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
        let predicate: Predicate<Student>? = {
            switch filter {
            case .all, .upper, .lower:
                // Level filtering will be done in-memory after fetch
                // (levelRaw is private, so can't be used in predicates)
                return nil
            case .presentNow:
                // Filter by IDs in the presentNow set
                let ids = presentNowIDs ?? []
                guard !ids.isEmpty else {
                    // Return predicate that matches nothing (always false condition)
                    return #Predicate<Student> { student in student.id != student.id }
                }
                return #Predicate<Student> { ids.contains($0.id) }
            }
        }()
        
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
        
        // Apply in-memory filters that can't be done in predicates:
        // 1. Level filtering (levelRaw is private, so can't be used in predicates)
        switch filter {
        case .all:
            break // No level filter needed
        case .upper:
            fetched = fetched.filter { $0.level == .upper }
        case .lower:
            fetched = fetched.filter { $0.level == .lower }
        case .presentNow:
            break // Already filtered by predicate
        }
        
        // 2. Test student filtering (requires checking against a set of names)
        fetched = TestStudentsFiltering.filterVisible(
            students: fetched,
            showTestStudents: showTestStudents,
            testStudentNames: testStudentNames
        )
        
        // 3. Search string filtering (SwiftData predicates don't support string contains well)
        if !searchString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchString.normalizedForComparison()
            fetched = fetched.filter { student in
                let firstName = student.firstName.lowercased()
                let lastName = student.lastName.lowercased()
                let fullName = student.fullName.lowercased()
                return firstName.contains(query) || lastName.contains(query) || fullName.contains(query)
            }
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
            let sorted = all.sorted { (lhs: Student, rhs: Student) -> Bool in
                lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
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
    /// Fetches all student lessons once and filters in memory to avoid repeated queries.
    private func computeDaysSinceLastLessonCache(
        for students: [Student],
        using modelContext: ModelContext,
        calendar: Calendar
    ) -> [UUID: Int] {
        // Fetch all student lessons once, sorted by date descending for efficiency
        let descriptor = FetchDescriptor<StudentLesson>(
            sortBy: [
                SortDescriptor(\StudentLesson.givenAt, order: .reverse),
                SortDescriptor(\StudentLesson.scheduledFor, order: .reverse),
                SortDescriptor(\StudentLesson.createdAt, order: .reverse)
            ]
        )
        let allStudentLessons = modelContext.safeFetch(descriptor)
        
        // Fetch lessons to exclude (parsha lessons)
        let lessonsDescriptor = FetchDescriptor<Lesson>()
        let allLessons = modelContext.safeFetch(lessonsDescriptor)
        let excludedLessonIDs: Set<UUID> = {
            func norm(_ s: String) -> String { s.normalizedForComparison() }
            let ids = allLessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map { $0.id }
            return Set(ids)
        }()
        
        // Filter to only given lessons that aren't excluded
        let givenLessons = allStudentLessons.filter { 
            $0.isGiven && !excludedLessonIDs.contains($0.resolvedLessonID) 
        }
        
        // Build a map of student ID to most recent lesson date
        var lastDateByStudent: [UUID: Date] = [:]
        for sl in givenLessons {
            let when = sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
            for sid in sl.resolvedStudentIDs {
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
        // Fetch all student lessons sorted by date descending
        // We fetch all because SwiftData predicates can't easily query JSON-encoded arrays
        let descriptor = FetchDescriptor<StudentLesson>(
            sortBy: [
                SortDescriptor(\StudentLesson.givenAt, order: .reverse),
                SortDescriptor(\StudentLesson.scheduledFor, order: .reverse),
                SortDescriptor(\StudentLesson.createdAt, order: .reverse)
            ]
        )
        let allStudentLessons = modelContext.safeFetch(descriptor)
        
        // Fetch lessons to exclude (parsha lessons)
        let lessonsDescriptor = FetchDescriptor<Lesson>()
        let allLessons = modelContext.safeFetch(lessonsDescriptor)
        let excludedLessonIDs: Set<UUID> = {
            func norm(_ s: String) -> String { s.normalizedForComparison() }
            let ids = allLessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map { $0.id }
            return Set(ids)
        }()
        
        // Find the most recent given lesson for this student
        let studentID = student.id
        let relevantLessons = allStudentLessons.filter { sl in
            sl.isGiven 
            && !excludedLessonIDs.contains(sl.resolvedLessonID)
            && sl.resolvedStudentIDs.contains(studentID)
        }
        
        guard let mostRecent = relevantLessons.first else {
            return -1 // No lesson found
        }
        
        let lastDate = mostRecent.givenAt ?? mostRecent.scheduledFor ?? mostRecent.createdAt
        
        // Calculate school days since last lesson
        return LessonAgeHelper.schoolDaysSinceCreation(
            createdAt: lastDate,
            asOf: Date(),
            using: modelContext,
            calendar: calendar
        )
    }
}

