import Foundation
import CoreData

@Observable
@MainActor
final class StudentsViewModel {
    // MARK: - Cache State
    var cachedAttendanceRecords: [CDAttendanceRecord] = []
    var cachedLessonAssignments: [CDLessonAssignment] = []
    var cachedLessons: [UUID: CDLesson] = [:]
    var cachedDaysSinceLastLesson: [UUID: Int] = [:]
    
    // MARK: - Change Detection
    private var lastLoadTimestamp: Date = .distantPast
    
    // MARK: - Filtering & Sorting
    func filteredStudents(
        viewContext: NSManagedObjectContext,
        filter: StudentsFilter,
        sortOrder: SortOrder,
        searchString: String = "",
        today: Date = Date(),
        presentNowIDs: Set<UUID>? = nil,
        showTestStudents: Bool = true,
        testStudentNames: String = ""
    ) -> [CDStudent] {
        // Note: level and presentNow filtering are done in-memory;
        // levelRaw is private and Core Data NSPredicate can't capture local Set variables.
        let descriptor = CDFetchRequest(CDStudent.self)
        descriptor.sortDescriptors = buildStudentSortDescriptors(for: sortOrder)
        var fetched = viewContext.safeFetch(descriptor)

        let query = searchString.trimmed().isEmpty ? nil : searchString.normalizedForComparison()
        let testFilter = TestStudentsFiltering.buildTestStudentFilter(
            showTestStudents: showTestStudents, testStudentNames: testStudentNames
        )
        fetched = applyStudentFilters(
            to: fetched, filter: filter, query: query,
            testFilter: testFilter, presentNowIDs: presentNowIDs
        )
        return applySortToFetched(fetched, sortOrder: sortOrder, today: today)
    }

    private func buildStudentSortDescriptors(for sortOrder: SortOrder) -> [NSSortDescriptor] {
        switch sortOrder {
        case .manual:
            return [NSSortDescriptor(key: "manualOrder", ascending: true)]
        case .alphabetical:
            return [NSSortDescriptor(key: "firstName", ascending: true), NSSortDescriptor(key: "lastName", ascending: true), NSSortDescriptor(key: "manualOrder", ascending: true)]
        case .age:
            return [NSSortDescriptor(key: "birthday", ascending: false), NSSortDescriptor(key: "manualOrder", ascending: true)]
        case .birthday:
            return [NSSortDescriptor(key: "manualOrder", ascending: true)]
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func applyStudentFilters(
        to students: [CDStudent],
        filter: StudentsFilter,
        query: String?,
        testFilter: (CDStudent) -> Bool,
        presentNowIDs: Set<UUID>?
    ) -> [CDStudent] {
        students.filter { student in
            // When showing withdrawn students, only show withdrawn; otherwise exclude them
            if filter == .withdrawn {
                if student.isEnrolled { return false }
            } else {
                if student.isWithdrawn { return false }
            }

            switch filter {
            case .all, .withdrawn: break
            case .upper: if student.level != .upper { return false }
            case .lower: if student.level != .lower { return false }
            case .presentNow:
                if let ids = presentNowIDs, !ids.isEmpty {
                    guard let studentID = student.id else { return false }
                    if !ids.contains(studentID) { return false }
                } else {
                    return false
                }
            }
            if !testFilter(student) { return false }
            if let query {
                let fn = student.firstName.lowercased()
                let ln = student.lastName.lowercased()
                let full = student.fullName.lowercased()
                if !fn.contains(query) && !ln.contains(query) && !full.contains(query) { return false }
            }
            return true
        }
    }

    private func applySortToFetched(_ students: [CDStudent], sortOrder: SortOrder, today: Date) -> [CDStudent] {
        switch sortOrder {
        case .manual, .age:
            return students
        case .alphabetical:
            return students.sorted { lhs, rhs in
                let order = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName)
                return order == .orderedSame ? lhs.manualOrder < rhs.manualOrder : order == .orderedAscending
            }
        case .birthday:
            let todayStart = Calendar.current.startOfDay(for: today)
            return students.sorted { lhs, rhs in
                let l = nextBirthday(from: lhs.birthday ?? Date(), relativeTo: todayStart)
                let r = nextBirthday(from: rhs.birthday ?? Date(), relativeTo: todayStart)
                return l == r ? lhs.manualOrder < rhs.manualOrder : l < r
            }
        }
    }

    func ensureInitialManualOrderIfNeeded(_ students: [CDStudent]) -> Bool {
        let all = students
        guard !all.isEmpty else { return false }
        let allZero = all.allSatisfy { $0.manualOrder == 0 }
        if allZero {
            let sorted = all.sorted(by: StudentSortComparator.byFirstName)
            var changed = false
            for (idx, s) in sorted.enumerated() where s.manualOrder != Int64(idx) {
                s.manualOrder = Int64(idx); changed = true
            }
            return changed
        }
        return false
    }

    func repairManualOrderUniquenessIfNeeded(_ students: [CDStudent]) -> Bool {
        let all = students
        guard !all.isEmpty else { return false }
        var seen = Set<Int64>()
        var duplicates: [CDStudent] = []
        // Keep first occurrence of each order and collect duplicates (e.g., newly added with default 0)
        for s in all.sorted(by: { $0.manualOrder < $1.manualOrder }) {
            if seen.contains(s.manualOrder) {
                duplicates.append(s)
            } else {
                seen.insert(s.manualOrder)
            }
        }
        if !duplicates.isEmpty {
            var maxOrder: Int64 = seen.max() ?? -1
            for s in duplicates {
                maxOrder += 1
                if s.manualOrder != maxOrder { s.manualOrder = maxOrder }
            }
            return true
        }
        return false
    }

    func mergeReorderedSubsetIntoAll(
        movingID: UUID, from fromIndex: Int, to toIndex: Int,
        current: [CDStudent], allStudents: [CDStudent]
    ) -> [UUID] {
        // Full list ordered by current manualOrder
        let allOrdered = allStudents.sorted { $0.manualOrder < $1.manualOrder }

        // IDs of the currently visible (filtered) subset
        let subsetIDs: [UUID] = current.compactMap(\.id)
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
            guard let sID = s.id else { continue }
            if subsetSet.contains(sID) {
                // Take next from the reordered subset
                if !subsetQueue.isEmpty {
                    newAllIDs.append(subsetQueue.removeFirst())
                }
            } else {
                newAllIDs.append(sID)
            }
        }
        return newAllIDs
    }

    // MARK: - Data Loading
    func loadDataOnDemand(
        mode: StudentMode,
        viewContext: NSManagedObjectContext,
        calendar: Calendar,
        students: [CDStudent]
    ) {
        // Load today's attendance records for roster view
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let descriptor: NSFetchRequest<CDAttendanceRecord> = NSFetchRequest(entityName: "CDAttendanceRecord")
        descriptor.predicate = NSPredicate(format: "date >= %@ AND date < %@", today as CVarArg, tomorrow as CVarArg)
        cachedAttendanceRecords = viewContext.safeFetch(descriptor)
        lastLoadTimestamp = Date()
    }
    
    // MARK: - Computed Helpers
    func presentNowIDs(from cachedRecords: [CDAttendanceRecord], calendar: Calendar) -> Set<UUID> {
        let today = calendar.startOfDay(for: Date())
        let filtered = cachedRecords.filter { 
            guard let recDate = $0.date else { return false }
            let recordDay = calendar.startOfDay(for: recDate)
            return recordDay == today && $0.status == .present
        }
        return Set(filtered.compactMap { UUID(uuidString: $0.studentID) })
    }
    
    func hiddenTestStudentIDs(
        students: [CDStudent],
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
            .compactMap(\.id))
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

}

// MARK: - CDLesson Age Cache
// Computes days since last lesson for multiple students efficiently.
// Fetches all lesson assignments once and filters in memory to avoid repeated queries.

extension StudentsViewModel {

    /// Shared data structure containing pre-fetched lesson data for efficient computation.
    private struct LessonQueryContext {
        let allLessonAssignments: [CDLessonAssignment]
        let excludedLessonIDs: Set<UUID>
        let calendar: Calendar
        let viewContext: NSManagedObjectContext

        init(viewContext: NSManagedObjectContext, calendar: Calendar) {
            self.calendar = calendar
            self.viewContext = viewContext

            // PERFORMANCE: Limit query to recent lessons (1 year) to avoid loading entire history
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date())
                ?? Date().addingTimeInterval(-365 * 24 * 3600)

            let descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "CDLessonAssignment")
            descriptor.predicate = NSPredicate(format: "createdAt >= %@", oneYearAgo as CVarArg)
            descriptor.sortDescriptors = [
                NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false),
                NSSortDescriptor(keyPath: \CDLessonAssignment.scheduledFor, ascending: false),
                NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: false)
            ]
            self.allLessonAssignments = viewContext.safeFetch(descriptor)

            // Fetch lessons to exclude (parsha lessons) - cache this as Set for O(1) lookup
            let lessonsDescriptor = NSFetchRequest<CDLesson>(entityName: "CDLesson")
            let allLessons = viewContext.safeFetch(lessonsDescriptor)
            func norm(_ s: String) -> String { s.normalizedForComparison() }
            let ids = allLessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.compactMap(\.id)
            self.excludedLessonIDs = Set(ids)
        }

        /// Returns all presented, non-excluded lesson assignments
        func presentedLessons() -> [CDLessonAssignment] {
            allLessonAssignments.filter {
                $0.isPresented && !excludedLessonIDs.contains($0.resolvedLessonID)
            }
        }
    }
    
    func computeDaysSinceLastLessonCache(
        for students: [CDStudent],
        using viewContext: NSManagedObjectContext,
        calendar: Calendar
    ) -> [UUID: Int] {
        // Build shared query context once
        let context = LessonQueryContext(viewContext: viewContext, calendar: calendar)
        let presented = context.presentedLessons()

        // Build a map of student ID to most recent lesson date
        var lastDateByStudent: [UUID: Date] = [:]
        for sl in presented {
            let when = sl.presentedAt ?? sl.scheduledFor ?? sl.createdAt ?? Date()
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
            guard let studentID = student.id else { continue }
            if let lastDate = lastDateByStudent[studentID] {
                // Use LessonAgeHelper to compute school days since last lesson
                result[studentID] = LessonAgeHelper.schoolDaysSinceCreation(
                    createdAt: lastDate,
                    asOf: Date(),
                    using: viewContext,
                    calendar: calendar
                )
            } else {
                // No lesson found - return -1 to indicate no lesson
                result[studentID] = -1
            }
        }
        
        return result
    }
    
    /// Computes days since last lesson for a single student.
    /// This is a convenience method that queries SwiftData directly.
    /// For multiple students, use computeDaysSinceLastLessonCache instead.
    func daysSinceLastLesson(
        for student: CDStudent,
        using viewContext: NSManagedObjectContext,
        calendar: Calendar = .current
    ) -> Int {
        // Reuse the shared logic by calling the batch method with a single student
        let result = computeDaysSinceLastLessonCache(
            for: [student],
            using: viewContext,
            calendar: calendar
        )
        return student.id.flatMap { result[$0] } ?? -1
    }
}
