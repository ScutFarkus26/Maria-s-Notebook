import Foundation
import CoreData

// What the roll reads off its rows and its day: no state of its own.
extension AttendanceViewModel {

    /// Reads the stored sort choice, falling back to last name for a notebook that has never set one.
    static func storedSortKey() -> SortKey {
        let raw = SyncedPreferencesStore.shared.string(forKey: sortKeyPreferenceKey)
        return raw.flatMap(SortKey.init(rawValue:)) ?? .lastName
    }

    var milestone: AttendanceSchoolDayCount.Milestone? { AttendanceSchoolDayCount.milestone(for: dayNumber) }

    /// "Day 37", "First Day" or "Day 100", or nil when there's no count.
    var dayLabel: String? {
        milestone?.title ?? dayNumber.map { "Day \($0)" }
    }

    // MARK: - The day

    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    /// A day after today: only absences and notes can be marked ahead.
    var isFuture: Bool { selectedDate > Calendar.current.startOfDay(for: Date()) }

    /// The statuses the menu offers on the day on screen.
    var menuStatuses: [AttendanceStatus] { AttendanceRules.menuStatuses(on: selectedDate) }

    var unmarkedCount: Int { rows.count { $0.status == .unmarked } }

    /// The children still unmarked, by full name: Close Arrival's list.
    var unmarkedNames: [String] {
        rows.filter { $0.status == .unmarked }.map(\.name)
    }

    /// Whether Close Arrival is on offer: someone's still unmarked, arrival
    /// is open, and the day has arrived. `canMark` is the caller's (a locked
    /// day can't be).
    func offersCloseArrival(canMark: Bool) -> Bool {
        canMark && !isFuture && phase == .arrival && unmarkedCount > 0
    }

    /// What a tap on an iPhone tile does, or nil when it does nothing: a
    /// present child during Late, and every tap on a day ahead.
    func statusAfterTap(for row: AttendanceRow) -> AttendanceStatus? {
        guard !isFuture else { return nil }
        return AttendanceRules.statusAfterTap(from: row.status, in: phase)
    }

    // MARK: - Filtering

    func visibleStudents(from all: [CDStudent]) -> [CDStudent] {
        TestStudentsFilter.filterVisible(all)
    }

    func sortedAndFiltered(students: [CDStudent]) -> [CDStudent] {
        switch sortKey {
        case .firstName:
            return students.sorted(by: StudentSortComparator.byFirstName)
        case .lastName:
            return students.sorted(by: StudentSortComparator.byLastName)
        }
    }

    // MARK: - Stats

    var countPresent: Int { rows.count { $0.status == .present } }
    var countAbsent: Int { rows.count { $0.status == .absent } }
    var countTardy: Int { rows.count { $0.status == .tardy } }
    var countLeftEarly: Int { rows.count { $0.status == .leftEarly } }

    /// "In Class" counts students who are either Present or Tardy.
    /// This is a derived metric for the header summary only and does not change stored data.
    var inClassCount: Int { countPresent + countTardy }
}
