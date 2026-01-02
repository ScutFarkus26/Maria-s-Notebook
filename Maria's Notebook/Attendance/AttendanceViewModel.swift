import Foundation
import SwiftUI
import Combine
import SwiftData

@MainActor
final class AttendanceViewModel: ObservableObject {
    @Published var selectedDate: Date
    // CloudKit compatibility: Use String keys since studentID is now String
    @Published var recordsByStudent: [String: AttendanceRecord] = [:]

    enum SortKey: String, CaseIterable { case firstName, lastName }
    @Published var sortKey: SortKey = .lastName

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
            return students.sorted { lhs, rhs in
                let c = lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName)
                if c == .orderedSame {
                    return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
                }
                return c == .orderedAscending
            }
        case .lastName:
            return students.sorted { lhs, rhs in
                let c = lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName)
                if c == .orderedSame {
                    return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
                }
                return c == .orderedAscending
            }
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
            var recordsByStudent: [String: AttendanceRecord] = [:]
            for record in filtered {
                if recordsByStudent[record.studentID] == nil {
                    recordsByStudent[record.studentID] = record
                }
            }
            self.recordsByStudent = recordsByStudent
        } catch {
            // For now, ignore errors; UI will simply show unmarked
        }
    }

    // MARK: - Actions
    func cycleStatus(for student: Student, modelContext: ModelContext) {
        // CloudKit compatibility: Convert UUID to String for lookup
        let studentIDString = student.id.uuidString
        guard let rec = recordsByStudent[studentIDString] else { return }
        let next = nextStatus(after: rec.status)
        let store = AttendanceStore(context: modelContext)
        if store.updateStatus(rec, to: next) {
            recordsByStudent[studentIDString]?.status = next
        }
    }

    private func nextStatus(after current: AttendanceStatus) -> AttendanceStatus {
        switch current {
        case .unmarked: return .present
        case .present: return .absent
        case .absent: return .tardy
        case .tardy: return .leftEarly
        case .leftEarly: return .present
        }
    }

    func updateNote(for student: Student, note: String?, modelContext: ModelContext) {
        // CloudKit compatibility: Convert UUID to String for lookup
        let studentIDString = student.id.uuidString
        guard let rec = recordsByStudent[studentIDString] else { return }
        let store = AttendanceStore(context: modelContext)
        if store.updateNote(rec, to: note) {
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            recordsByStudent[studentIDString]?.note = trimmed.isEmpty ? nil : trimmed
        }
    }

    func markAllPresent(students: [Student], modelContext: ModelContext) {
        let store = AttendanceStore(context: modelContext)
        do {
            let updated = try store.markAllPresent(for: selectedDate, students: students)
            // CloudKit compatibility: Convert UUIDs to Strings for comparison
            let allowed = Set(students.map { $0.id.uuidString })
            for rec in updated where allowed.contains(rec.studentID) {
                recordsByStudent[rec.studentID] = rec
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
                recordsByStudent[rec.studentID] = rec
            }
        } catch { }
    }

    // MARK: - Stats
    var countPresent: Int { recordsByStudent.values.filter { $0.status == .present }.count }
    var countAbsent: Int { recordsByStudent.values.filter { $0.status == .absent }.count }
    var countTardy: Int { recordsByStudent.values.filter { $0.status == .tardy }.count }
    var countLeftEarly: Int { recordsByStudent.values.filter { $0.status == .leftEarly }.count }
    var countUnmarked: Int { recordsByStudent.values.filter { $0.status == .unmarked }.count }

    /// "In Class" counts students who are either Present or Tardy.
    /// This is a derived metric for the header summary only and does not change stored data.
    var inClassCount: Int { countPresent + countTardy }
}

