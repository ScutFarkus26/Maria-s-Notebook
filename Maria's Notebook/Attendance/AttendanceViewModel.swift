import Foundation
import SwiftUI
import CoreData
import OSLog

@Observable
@MainActor
final class AttendanceViewModel {
    private static let logger = Logger.attendance
    var selectedDate: Date
    // CloudKit compatibility: Use String keys since studentID is now String
    var recordsByStudentID: [String: CDAttendanceRecord] = [:]
    /// Size of the loaded roster; students without a record count as unmarked.
    private(set) var rosterCount = 0

    enum SortKey: String, CaseIterable { case firstName, lastName }

    /// The picker's last choice, remembered across launches (and across devices, since the key syncs).
    static let sortKeyPreferenceKey = "Attendance.sortKey"

    private(set) var sortKey: SortKey = AttendanceViewModel.storedSortKey()

    init(selectedDate: Date = Date()) {
        self.selectedDate = selectedDate.normalizedDay()
    }

    /// Reads the stored sort choice, falling back to last name for a notebook that has never set one.
    static func storedSortKey() -> SortKey {
        let raw = SyncedPreferencesStore.shared.string(forKey: sortKeyPreferenceKey)
        return raw.flatMap(SortKey.init(rawValue:)) ?? .lastName
    }

    /// Changes the sort and writes it back, so reopening attendance lands on the same order.
    func setSortKey(_ newValue: SortKey) {
        guard newValue != sortKey else { return }
        sortKey = newValue
        SyncedPreferencesStore.shared.set(newValue.rawValue, forKey: Self.sortKeyPreferenceKey)
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

    // MARK: - Loading
    func load(for date: Date? = nil, students: [CDStudent], modelContext: NSManagedObjectContext) {
        let target = (date ?? selectedDate).normalizedDay()
        selectedDate = target
        rosterCount = students.count
        let store = CDAttendanceStore(context: modelContext)
        do {
            // Load existing records only — a student without one renders as
            // unmarked, and the first mark creates the record (`ensureRecord`).
            let records = try store.loadRecords(for: target)
            // CloudKit compatibility: Convert UUIDs to Strings for comparison
            let allowed = Set(students.compactMap { $0.id?.uuidString })
            let filtered = records.filter { allowed.contains($0.studentID) }
            // Collapse CloudKit duplicates to the same winner reports count.
            var recordsByStudentID: [String: CDAttendanceRecord] = [:]
            for record in filtered.deduplicatedPerStudentDay() {
                recordsByStudentID[record.studentID] = record
            }
            self.recordsByStudentID = recordsByStudentID
        } catch {
            Self.logger.warning("Failed to load records: \(error)")
        }
    }

    // MARK: - Actions
    func cycleStatus(for student: CDStudent, modelContext: NSManagedObjectContext) {
        // CloudKit compatibility: Convert UUID to String for lookup
        let studentIDString = student.cloudKitKey
        let store = CDAttendanceStore(context: modelContext)
        do {
            // First mark on a virtual (unmarked) row creates the record here;
            // the caller saves immediately after, so it can't linger unsaved.
            guard let rec = try recordsByStudentID[studentIDString]
                ?? store.ensureRecord(for: student, on: selectedDate) else { return }
            let next = rec.status.next()
            if store.updateStatus(rec, to: next) {
                recordsByStudentID[studentIDString] = rec
                HapticService.shared.selection()
            }
        } catch {
            Self.logger.warning("Failed to cycle status: \(error)")
        }
    }

    func updateNote(for student: CDStudent, note: String?, modelContext: NSManagedObjectContext) {
        // CloudKit compatibility: Convert UUID to String for lookup
        let studentIDString = student.cloudKitKey
        let store = CDAttendanceStore(context: modelContext)
        do {
            guard let rec = try recordsByStudentID[studentIDString]
                ?? store.ensureRecord(for: student, on: selectedDate) else { return }
            if store.updateNote(rec, to: note) {
                recordsByStudentID[studentIDString] = rec
            }
        } catch {
            Self.logger.warning("Failed to update note: \(error)")
        }
    }

    func updateAbsenceReason(for student: CDStudent, reason: AbsenceReason, modelContext: NSManagedObjectContext) {
        // CloudKit compatibility: Convert UUID to String for lookup
        let studentIDString = student.cloudKitKey
        guard let rec = recordsByStudentID[studentIDString] else { return }
        // Only allow setting absence reason if status is absent
        guard rec.status == .absent else { return }
        let store = CDAttendanceStore(context: modelContext)
        if store.updateAbsenceReason(rec, to: reason) {
            recordsByStudentID[studentIDString]?.absenceReason = reason
        }
    }

    func markAllPresent(students: [CDStudent], modelContext: NSManagedObjectContext) {
        let store = CDAttendanceStore(context: modelContext)
        do {
            let updated = try store.markAllPresent(for: selectedDate, students: students)
            // CloudKit compatibility: Convert UUIDs to Strings for comparison
            let allowed = Set(students.compactMap { $0.id?.uuidString })
            for rec in updated where allowed.contains(rec.studentID) {
                recordsByStudentID[rec.studentID] = rec
            }
        } catch {
            Self.logger.warning("Failed to mark all present: \(error)")
        }
    }

    func resetDay(students: [CDStudent], modelContext: NSManagedObjectContext) {
        let store = CDAttendanceStore(context: modelContext)
        do {
            let updated = try store.resetDay(for: selectedDate, students: students)
            // CloudKit compatibility: Convert UUIDs to Strings for comparison
            let allowed = Set(students.compactMap { $0.id?.uuidString })
            for rec in updated where allowed.contains(rec.studentID) {
                recordsByStudentID[rec.studentID] = rec
            }
        } catch {
            Self.logger.warning("Failed to reset day: \(error)")
        }
    }

    // MARK: - Stats
    var countPresent: Int { recordsByStudentID.values.filter { $0.status == .present }.count }
    var countAbsent: Int { recordsByStudentID.values.filter { $0.status == .absent }.count }
    var countTardy: Int { recordsByStudentID.values.filter { $0.status == .tardy }.count }
    var countLeftEarly: Int { recordsByStudentID.values.filter { $0.status == .leftEarly }.count }
    /// Roster members with no record are unmarked too — records are only created on first mark.
    var countUnmarked: Int {
        max(0, rosterCount - (countPresent + countAbsent + countTardy + countLeftEarly))
    }

    /// "In Class" counts students who are either Present or Tardy.
    /// This is a derived metric for the header summary only and does not change stored data.
    var inClassCount: Int { countPresent + countTardy }
}
