import Foundation
import CoreData
import SwiftUI

@Observable
final class StudentsViewModel {
    // MARK: - Cache State
    var cachedAttendanceRecords: [CDAttendanceRecord] = []
    var cachedLessonAssignments: [CDLessonAssignment] = []
    var cachedLessons: [UUID: CDLesson] = [:]
    var cachedDaysSinceLastLesson: [UUID: Int] = [:]
    var cachedNextLessonNames: [UUID: String] = [:]
    var cachedLastObservationDates: [UUID: Date] = [:]
    
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
        // CDNote: level and presentNow filtering are done in-memory;
        // levelRaw is private and Core Data NSPredicate can't capture local Set variables.
        let descriptor = CDFetchRequest(CDStudent.self)
        descriptor.sortDescriptors = buildStudentSortDescriptors(for: sortOrder)
        var fetched = viewContext.safeFetch(descriptor)

        let query = searchString.trimmed().isEmpty ? nil : searchString.normalizedForComparison()
        let testFilter = TestStudentsFilter.buildTestStudentFilter(
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
            return [
                NSSortDescriptor(key: "firstName", ascending: true),
                NSSortDescriptor(key: "lastName", ascending: true),
                NSSortDescriptor(key: "manualOrder", ascending: true)
            ]
        case .age:
            return [
                NSSortDescriptor(key: "birthday", ascending: false),
                NSSortDescriptor(key: "manualOrder", ascending: true)
            ]
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
            // When showing former students, only show former (withdrawn or transferred);
            // otherwise exclude them from the active roster.
            if filter == .withdrawn {
                if student.isEnrolled { return false }
            } else {
                if !student.isEnrolled { return false }
            }

            switch filter {
            case .all, .withdrawn: break
            case .upper: if student.level != .upper { return false }
            case .lower: if student.level != .lower { return false }
            case .adolescent: if student.level != .adolescent { return false }
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
            let todayStart = AppCalendar.shared.startOfDay(for: today)
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
            subset.move(fromOffsets: IndexSet(integer: sFrom), toOffset: toIndex)
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
        viewContext: NSManagedObjectContext,
        calendar: Calendar,
        students: [CDStudent]
    ) {
        // Load today's attendance records for the present-now filter and row indicators
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let descriptor: NSFetchRequest<CDAttendanceRecord> = NSFetchRequest(entityName: "AttendanceRecord")
        descriptor.predicate = NSPredicate(format: "date >= %@ AND date < %@", today as CVarArg, tomorrow as CVarArg)
        cachedAttendanceRecords = viewContext.safeFetch(descriptor)

        // Days-since-last-lesson feeds the row accessory in A–Z/manual sort
        cachedDaysSinceLastLesson = computeDaysSinceLastLessonCache(
            for: students, using: viewContext, calendar: calendar
        )
        loadTableCaches(students: students, viewContext: viewContext)
        lastLoadTimestamp = Date()
    }

    private func loadTableCaches(students: [CDStudent], viewContext: NSManagedObjectContext) {
        let studentIDs = Set(students.compactMap(\.id))

        let lessonRequest: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
        let lessons = viewContext.safeFetch(lessonRequest)
        cachedLessons = Dictionary(
            lessons.compactMap { lesson in lesson.id.map { ($0, lesson) } },
            uniquingKeysWith: { first, _ in first }
        )
        cachedNextLessonNames = Dictionary(
            uniqueKeysWithValues: students.compactMap { student in
                guard let studentID = student.id,
                      let lessonName = student.nextLessonUUIDs.lazy.compactMap({ self.cachedLessons[$0]?.name }).first
                else { return nil }
                return (studentID, lessonName)
            }
        )

        let noteRequest: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
        noteRequest.predicate = NSPredicate(format: "searchIndexStudentID != nil")
        let directNotes = viewContext.safeFetch(noteRequest)

        let linkRequest: NSFetchRequest<CDNoteStudentLink> = NSFetchRequest(entityName: "NoteStudentLink")
        linkRequest.relationshipKeyPathsForPrefetching = ["note"]
        let links = viewContext.safeFetch(linkRequest)

        var latest: [UUID: Date] = [:]
        for note in directNotes {
            guard let studentID = note.searchIndexStudentID,
                  studentIDs.contains(studentID),
                  let date = note.updatedAt ?? note.createdAt else { continue }
            latest[studentID] = max(latest[studentID] ?? .distantPast, date)
        }
        for link in links {
            guard let studentID = link.studentIDUUID,
                  studentIDs.contains(studentID),
                  let note = link.note,
                  !note.scopeIsAll,
                  let date = note.updatedAt ?? note.createdAt else { continue }
            latest[studentID] = max(latest[studentID] ?? .distantPast, date)
        }
        cachedLastObservationDates = latest
    }
    
    // MARK: - Computed Helpers
    /// Students marked in the room today. Tardy counts as here — a late arrival is
    /// still present — so this matches the Today header's "in" count. Left-early
    /// students have gone home and are not counted.
    func presentNowIDs(from cachedRecords: [CDAttendanceRecord], calendar: Calendar) -> Set<UUID> {
        let today = calendar.startOfDay(for: Date())
        let filtered = cachedRecords.filter {
            guard let recDate = $0.date else { return false }
            let recordDay = calendar.startOfDay(for: recDate)
            return recordDay == today && ($0.status == .present || $0.status == .tardy)
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
        let cal = AppCalendar.shared
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
// Reads the presented assignments of the last year once — as five columns, not
// as objects — and folds them into one date per student.

extension StudentsViewModel {

    /// One presented assignment reduced to the three facts the day count needs.
    private struct PresentedAssignment {
        let lessonID: UUID?
        let studentIDs: [UUID]
        let when: Date
    }

    /// The presented assignments of the last year, minus the ones for Parsha lessons.
    ///
    /// Both queries are shaped to read as little as the answer needs. The lesson
    /// query asks the store for the Parsha rows instead of folding every lesson
    /// name in Swift; the assignment query filters on `stateRaw` in SQL and reads
    /// dictionaries rather than faulting a year of objects — the old object path
    /// also read `resolvedLessonID` per row, which is a separate `SELECT` each.
    private struct LessonQueryContext {
        let presentedAssignments: [PresentedAssignment]

        init(viewContext: NSManagedObjectContext, calendar: Calendar) {
            // PERFORMANCE: Limit query to recent lessons (1 year) to avoid loading entire history
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date())
                ?? Date().addingTimeInterval(-365 * 24 * 3600)

            let excluded = Self.parshaLessonIDs(in: viewContext)
            // A row whose `lessonID` doesn't parse used to compare against a fresh
            // UUID, which is never in the excluded set — so it was kept. Keep it.
            presentedAssignments = Self.presentedRows(since: oneYearAgo, in: viewContext)
                .filter { row in
                    guard let lessonID = row.lessonID else { return true }
                    return !excluded.contains(lessonID)
                }
        }

        /// IDs of the lessons the day count ignores.
        ///
        /// `normalizedForComparison()` is trim + lowercase, which no predicate can
        /// express, so the store narrows to the rows that could possibly match and
        /// Swift makes the same decision it always did on that handful. `[c]` only —
        /// the fold is case-insensitive but *not* diacritic-insensitive.
        private static func parshaLessonIDs(in context: NSManagedObjectContext) -> Set<UUID> {
            let request = NSFetchRequest<CDLesson>(entityName: "Lesson")
            request.predicate = NSPredicate(
                format: "area CONTAINS[c] %@ OR sequence CONTAINS[c] %@", "parsha", "parsha"
            )
            let candidates = context.safeFetch(request).filter {
                $0.area.normalizedForComparison() == "parsha"
                    || $0.sequence.normalizedForComparison() == "parsha"
            }
            return Set(candidates.compactMap(\.id))
        }

        private static func presentedRows(
            since cutoff: Date,
            in context: NSManagedObjectContext
        ) -> [PresentedAssignment] {
            let predicate = NSPredicate(
                format: "createdAt >= %@ AND stateRaw == %@",
                cutoff as CVarArg, LessonAssignmentState.presented.rawValue
            )
            // A dictionary-result fetch can't see unsaved inserts, so a dirty
            // context still takes the object path — the answer has to be identical.
            if !context.hasChanges, let rows = dictionaryRows(matching: predicate, in: context) {
                return rows
            }
            let request = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
            request.predicate = predicate
            request.returnsObjectsAsFaults = false
            request.fetchBatchSize = 200
            return context.safeFetch(request).map {
                PresentedAssignment(
                    lessonID: $0.lessonIDUUID,
                    studentIDs: $0.studentUUIDs,
                    when: $0.presentedAt ?? $0.scheduledFor ?? $0.createdAt ?? Date()
                )
            }
        }

        /// `nil` when the fetch fails, so the caller falls back to the object path.
        private static func dictionaryRows(
            matching predicate: NSPredicate,
            in context: NSManagedObjectContext
        ) -> [PresentedAssignment]? {
            let request = NSFetchRequest<NSDictionary>(entityName: "LessonAssignment")
            request.resultType = .dictionaryResultType
            request.predicate = predicate
            request.propertiesToFetch = [
                "presentedAt", "scheduledFor", "createdAt", "lessonID", "_studentIDsData"
            ]
            guard let rows = try? context.fetch(request) else { return nil }
            return rows.map { row in
                let when = (row["presentedAt"] as? Date)
                    ?? (row["scheduledFor"] as? Date)
                    ?? (row["createdAt"] as? Date)
                    ?? Date()
                // Same decoding the `studentIDs` accessor does, straight off the blob.
                let ids = CloudKitStringArrayStorage.decode(from: row["_studentIDsData"] as? Data)
                return PresentedAssignment(
                    lessonID: (row["lessonID"] as? String).flatMap { UUID(uuidString: $0) },
                    studentIDs: ids.compactMap { UUID(uuidString: $0) },
                    when: when
                )
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

        // Build a map of student ID to most recent lesson date
        var lastDateByStudent: [UUID: Date] = [:]
        for assignment in context.presentedAssignments {
            let when = assignment.when
            for sid in assignment.studentIDs {
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
                    using: viewContext
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
