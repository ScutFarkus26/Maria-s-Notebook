import Foundation
import CoreData
import SwiftUI

/// The roster screen's per-child signals and its filter/sort rules.
///
/// The students themselves come from `RosterStore` (already live and
/// observable), so this model never fetches the Student table: it filters and
/// sorts the store's array in memory. What it caches is what the store does
/// not know: today's attendance, and the lesson and observation facts behind
/// each row's signals (`StudentsViewModel+Caches`). Each is rebuilt only when
/// one of its own inputs changed, or the day turned over.
@Observable
final class StudentsViewModel {
    // MARK: - Caches

    /// Today's mark per child, from today's attendance rows.
    private(set) var presenceByStudent: [UUID: StudentSignals.Presence] = [:]
    /// True once anyone has a mark today; until then the roster says
    /// attendance hasn't been taken instead of showing everyone unmarked.
    private(set) var attendanceTaken = false
    /// Whether today is a school day, read with today's attendance.
    private(set) var isSchoolDayToday = true
    /// True on a school day before anyone has a mark.
    var showsAttendanceNotTaken: Bool { isSchoolDayToday && !attendanceTaken }
    /// School days since the last presented lesson; -1 when there is none in a year.
    var cachedDaysSinceLastLesson: [UUID: Int] = [:]
    var cachedNextLessonNames: [UUID: String] = [:]
    var cachedLastObservationDates: [UUID: Date] = [:]

    // MARK: - Change Detection (see StudentsViewModel+Caches.swift)

    /// Flips when an attendance row changes.
    @ObservationIgnored var attendanceInputs: ManagedObjectChangeFlag?
    /// The day today's attendance was last loaded for.
    @ObservationIgnored var attendanceLoadedFor: Date?
    /// Attendance loads actually run (for tests pinning the gate).
    @ObservationIgnored var attendanceLoadCount = 0
    /// Flips when anything the table caches read changes (see `tableCacheInputEntities`).
    @ObservationIgnored var tableCacheInputs: ManagedObjectChangeFlag?
    /// The day and counter epoch the table caches were last built under.
    @ObservationIgnored var tableCachesBuiltFor: TableCacheStamp?
    /// Full table-cache builds actually run (for tests pinning the gate).
    @ObservationIgnored var tableCacheBuildCount = 0

    // MARK: - Signals

    func signals(for studentID: UUID?) -> StudentSignals {
        guard let studentID else { return StudentSignals() }
        let days = cachedDaysSinceLastLesson[studentID]
        return StudentSignals(
            presence: presenceByStudent[studentID] ?? .unmarked,
            schoolDaysSinceLesson: days.flatMap { $0 >= 0 ? $0 : nil },
            lastObserved: cachedLastObservationDates[studentID],
            nextLessonName: cachedNextLessonNames[studentID]
        )
    }

    /// Children marked here today (present or tardy; left-early children have gone home).
    var presentNowIDs: Set<UUID> {
        Set(presenceByStudent.compactMap { $0.value == .here ? $0.key : nil })
    }

    /// Children due for a lesson among `students`.
    func dueIDs(among students: [CDStudent]) -> Set<UUID> {
        Set(students.compactMap { student in
            guard let id = student.id, signals(for: id).isDueForLesson else { return nil }
            return id
        })
    }

    // MARK: - Filtering & Sorting

    /// The roster narrowed and ordered for display. Pure: `students` is the
    /// workspace roster (`RosterStore.all`), filtered and sorted in memory.
    static func filteredStudents(
        _ students: [CDStudent],
        filter: StudentsFilter,
        sortOrder: SortOrder,
        searchString: String = "",
        today: Date = Date(),
        presentNowIDs: Set<UUID> = [],
        dueIDs: Set<UUID> = [],
        showTestStudents: Bool = true,
        testStudentNames: String = ""
    ) -> [CDStudent] {
        let query = searchString.trimmed().isEmpty ? nil : searchString.normalizedForComparison()
        let isVisible = TestStudentsFilter.buildTestStudentFilter(
            showTestStudents: showTestStudents, testStudentNames: testStudentNames
        )
        let matching = students.filter { student in
            // Former students (withdrawn or transferred) only in their own list.
            guard student.isEnrolled == (filter != .withdrawn) else { return false }
            if let level = filter.level, student.level != level { return false }
            if filter == .presentNow || filter == .dueForLesson {
                guard let id = student.id else { return false }
                let ids = filter == .presentNow ? presentNowIDs : dueIDs
                if !ids.contains(id) { return false }
            }
            guard isVisible(student) else { return false }
            if let query {
                let names = [student.firstName, student.lastName, student.fullName].map { $0.lowercased() }
                if !names.contains(where: { $0.contains(query) }) { return false }
            }
            return true
        }
        return sorted(matching.uniqueByID, by: sortOrder, today: today)
    }

    private static func sorted(_ students: [CDStudent], by sortOrder: SortOrder, today: Date) -> [CDStudent] {
        switch sortOrder {
        case .manual:
            return students.sorted { lhs, rhs in
                lhs.manualOrder == rhs.manualOrder
                    ? byName(lhs, rhs)
                    : lhs.manualOrder < rhs.manualOrder
            }
        case .alphabetical:
            return students.sorted(by: byName)
        case .age:
            // Youngest first; children with no birthday on file last.
            return students.sorted { lhs, rhs in
                switch (lhs.birthday, rhs.birthday) {
                case let (l?, r?) where l != r: return l > r
                case (.some, nil): return true
                case (nil, .some): return false
                default: return lhs.manualOrder < rhs.manualOrder
                }
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

    private static func byName(_ lhs: CDStudent, _ rhs: CDStudent) -> Bool {
        let order = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName)
        return order == .orderedSame ? lhs.manualOrder < rhs.manualOrder : order == .orderedAscending
    }

    private static func nextBirthday(from birthday: Date, relativeTo today: Date) -> Date {
        AgeUtils.nextBirthday(for: birthday, today: today, calendar: AppCalendar.shared) ?? .distantFuture
    }

    // MARK: - Manual Order

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

    /// Rebuilds everything now (first appearance, tests).
    func loadDataOnDemand(
        viewContext: NSManagedObjectContext,
        calendar: Calendar,
        students: [CDStudent]
    ) {
        loadAttendance(viewContext: viewContext, calendar: calendar)
        buildTableCaches(viewContext: viewContext, calendar: calendar, students: students)
    }

    /// Reloads only what moved since the last call: today's attendance when an
    /// attendance row changed or the day turned over; the lesson and
    /// observation caches when one of their inputs changed, or the day (or
    /// counter epoch) turned over. An attendance tap rebuilds nothing else.
    func refreshIfNeeded(
        viewContext: NSManagedObjectContext,
        calendar: Calendar,
        students: [CDStudent]
    ) {
        let stamp = TableCacheStamp(calendar: calendar)
        let attendanceMoved = attendanceFlag(for: viewContext).consume(pendingIn: viewContext)
        if attendanceMoved || attendanceLoadedFor != stamp.day {
            loadAttendance(viewContext: viewContext, calendar: calendar)
        }
        let inputsMoved = tableCacheFlag(for: viewContext).consume(pendingIn: viewContext)
        if inputsMoved || tableCachesBuiltFor != stamp {
            buildTableCaches(viewContext: viewContext, calendar: calendar, students: students)
        }
    }

    private func loadAttendance(viewContext: NSManagedObjectContext, calendar: Calendar) {
        // Cleared before the load, so a change that lands during it counts.
        _ = attendanceFlag(for: viewContext).consume(pendingIn: viewContext)
        attendanceLoadCount += 1
        let today = calendar.startOfDay(for: Date())
        attendanceLoadedFor = today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", today as CVarArg, tomorrow as CVarArg)
        let (presence, taken) = Self.presence(from: viewContext.safeFetch(request))
        if presence != presenceByStudent { presenceByStudent = presence }
        if taken != attendanceTaken { attendanceTaken = taken }
        let schoolDay = SchoolDayChecker.isSchoolDay(today, using: viewContext)
        if schoolDay != isSchoolDayToday { isSchoolDayToday = schoolDay }
    }

    /// Today's mark per child. A child with two rows for the day (a CloudKit
    /// duplicate) takes the marked one.
    static func presence(
        from records: [CDAttendanceRecord]
    ) -> (byStudent: [UUID: StudentSignals.Presence], taken: Bool) {
        var byStudent: [UUID: StudentSignals.Presence] = [:]
        var taken = false
        for record in records {
            guard let id = UUID(uuidString: record.studentID) else { continue }
            let presence: StudentSignals.Presence
            switch record.status {
            case .present, .tardy: presence = .here
            case .absent: presence = .absent
            case .leftEarly: presence = .leftEarly
            case .unmarked: presence = .unmarked
            }
            if presence != .unmarked { taken = true }
            if byStudent[id] == nil || byStudent[id] == .unmarked {
                byStudent[id] = presence
            }
        }
        return (byStudent, taken)
    }

    private func buildTableCaches(viewContext: NSManagedObjectContext, calendar: Calendar, students: [CDStudent]) {
        // Cleared before the build, so a change that lands during it counts.
        _ = tableCacheFlag(for: viewContext).consume(pendingIn: viewContext)
        tableCachesBuiltFor = TableCacheStamp(calendar: calendar)
        tableCacheBuildCount += 1
        let days = computeDaysSinceLastLessonCache(for: students, using: viewContext, calendar: calendar)
        if days != cachedDaysSinceLastLesson { cachedDaysSinceLastLesson = days }

        let lessons = Self.nextLessons(for: students, in: viewContext)
        let lessonNames: [UUID: String] = Dictionary(
            lessons.compactMap { lesson in lesson.id.map { ($0, lesson.name) } },
            uniquingKeysWith: { first, _ in first }
        )
        let nextNames = Dictionary(
            students.compactMap { student -> (UUID, String)? in
                guard let studentID = student.id,
                      let name = student.nextLessonUUIDs.lazy.compactMap({ lessonNames[$0] }).first
                else { return nil }
                return (studentID, name)
            },
            uniquingKeysWith: { first, _ in first }
        )
        if nextNames != cachedNextLessonNames { cachedNextLessonNames = nextNames }

        let latest = Self.latestObservationDates(for: Set(students.compactMap(\.id)), in: viewContext)
        if latest != cachedLastObservationDates { cachedLastObservationDates = latest }
    }
}
