import Foundation
import SwiftUI
import SwiftData

@Observable
@MainActor
final class AttendanceViewModel {
    var selectedDate: Date
    // CloudKit compatibility: Use String keys since studentID is now String
    var recordsByStudentID: [String: AttendanceRecord] = [:]

    enum SortKey: String, CaseIterable { case firstName, lastName }
    var sortKey: SortKey = .lastName

    init(selectedDate: Date = Date()) {
        self.selectedDate = selectedDate.normalizedDay()
    }

    // MARK: - Filtering

    func visibleStudents(from all: [Student]) -> [Student] {
        TestStudentsFilter.filterVisible(all)
    }

    func sortedAndFiltered(students: [Student]) -> [Student] {
        switch sortKey {
        case .firstName:
            return students.sorted(by: StudentSortComparator.byFirstName)
        case .lastName:
            return students.sorted(by: StudentSortComparator.byLastName)
        }
    }

    // MARK: - Loading
    func load(for date: Date? = nil, students: [Student], modelContext: ModelContext) {
        let target = (date ?? selectedDate).normalizedDay()
        selectedDate = target
        let store = AttendanceStore(context: modelContext)
        do {
            let result = try store.loadOrCreateRecords(for: target, students: students)
            let records = result.records
            // CloudKit compatibility: Convert UUIDs to Strings for comparison
            let allowed = Set(students.map { $0.id.uuidString })
            let filtered = records.filter { allowed.contains($0.studentID) }
            // Build dictionary safely, handling potential duplicates by keeping the first occurrence
            var recordsByStudentID: [String: AttendanceRecord] = [:]
            for record in filtered {
                recordsByStudentID.insertIfAbsent(record, forKey: record.studentID)
            }
            self.recordsByStudentID = recordsByStudentID
        } catch {
            // For now, ignore errors; UI will simply show unmarked
        }
    }

    // MARK: - Actions
    func cycleStatus(for student: Student, modelContext: ModelContext) {
        // CloudKit compatibility: Convert UUID to String for lookup
        let studentIDString = student.cloudKitKey
        guard let rec = recordsByStudentID[studentIDString] else { return }
        let next = rec.status.next()
        let store = AttendanceStore(context: modelContext)
        if store.updateStatus(rec, to: next) {
            recordsByStudentID[studentIDString]?.status = next
        }
    }

    func updateNote(for student: Student, note: String?, modelContext: ModelContext) {
        // CloudKit compatibility: Convert UUID to String for lookup
        let studentIDString = student.cloudKitKey
        guard let rec = recordsByStudentID[studentIDString] else { return }
        let store = AttendanceStore(context: modelContext)
        if store.updateNote(rec, to: note) {
            let trimmed = note?.trimmed() ?? ""
            recordsByStudentID[studentIDString]?.note = trimmed.isEmpty ? nil : trimmed
        }
    }

    func updateAbsenceReason(for student: Student, reason: AbsenceReason, modelContext: ModelContext) {
        // CloudKit compatibility: Convert UUID to String for lookup
        let studentIDString = student.cloudKitKey
        guard let rec = recordsByStudentID[studentIDString] else { return }
        // Only allow setting absence reason if status is absent
        guard rec.status == .absent else { return }
        let store = AttendanceStore(context: modelContext)
        if store.updateAbsenceReason(rec, to: reason) {
            recordsByStudentID[studentIDString]?.absenceReason = reason
        }
    }

    func markAllPresent(students: [Student], modelContext: ModelContext) {
        let store = AttendanceStore(context: modelContext)
        do {
            let updated = try store.markAllPresent(for: selectedDate, students: students)
            // CloudKit compatibility: Convert UUIDs to Strings for comparison
            let allowed = Set(students.map { $0.id.uuidString })
            for rec in updated where allowed.contains(rec.studentID) {
                recordsByStudentID[rec.studentID] = rec
            }
        } catch { }
    }

    func resetDay(students: [Student], modelContext: ModelContext) {
        let store = AttendanceStore(context: modelContext)
        do {
            let updated = try store.resetDay(for: selectedDate, students: students)
            // CloudKit compatibility: Convert UUIDs to Strings for comparison
            let allowed = Set(students.map { $0.id.uuidString })
            for rec in updated where allowed.contains(rec.studentID) {
                recordsByStudentID[rec.studentID] = rec
            }
        } catch { }
    }

    // MARK: - Stats
    var countPresent: Int { recordsByStudentID.values.filter { $0.status == .present }.count }
    var countAbsent: Int { recordsByStudentID.values.filter { $0.status == .absent }.count }
    var countTardy: Int { recordsByStudentID.values.filter { $0.status == .tardy }.count }
    var countLeftEarly: Int { recordsByStudentID.values.filter { $0.status == .leftEarly }.count }
    var countUnmarked: Int { recordsByStudentID.values.filter { $0.status == .unmarked }.count }

    /// "In Class" counts students who are either Present or Tardy.
    /// This is a derived metric for the header summary only and does not change stored data.
    var inClassCount: Int { countPresent + countTardy }
}

