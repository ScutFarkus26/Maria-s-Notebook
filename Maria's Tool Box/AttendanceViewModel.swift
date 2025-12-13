import Foundation
import SwiftUI
import Combine
import SwiftData

@MainActor
final class AttendanceViewModel: ObservableObject {
    @Published var selectedDate: Date
    @Published var recordsByStudent: [UUID: AttendanceRecord] = [:]

    enum LevelFilter: String, CaseIterable { case all, lower, upper }
    @Published var levelFilter: LevelFilter = .all

    enum SortKey: String, CaseIterable { case firstName, lastName }
    @Published var sortKey: SortKey = .lastName

    init(selectedDate: Date = Date()) {
        self.selectedDate = selectedDate.normalizedDay()
    }

    // MARK: - Filtering
    private var excludedStudentNames: Set<String> { ["lil d", "danny de berry", "lil dan d"] }

    private func isExcluded(_ student: Student) -> Bool {
        let name = student.fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return excludedStudentNames.contains(name)
    }

    func visibleStudents(from all: [Student]) -> [Student] {
        all.filter { !isExcluded($0) }
    }

    func sortedAndFiltered(students: [Student]) -> [Student] {
        let base: [Student]
        switch levelFilter {
        case .all: base = students
        case .lower: base = students.filter { $0.level == .lower }
        case .upper: base = students.filter { $0.level == .upper }
        }
        switch sortKey {
        case .firstName:
            return base.sorted { lhs, rhs in
                let c = lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName)
                if c == .orderedSame {
                    return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
                }
                return c == .orderedAscending
            }
        case .lastName:
            return base.sorted { lhs, rhs in
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
            let allowed = Set(students.map { $0.id })
            let filtered = records.filter { allowed.contains($0.studentID) }
            self.recordsByStudent = Dictionary(uniqueKeysWithValues: filtered.map { ($0.studentID, $0) })
        } catch {
            // For now, ignore errors; UI will simply show unmarked
        }
    }

    // MARK: - Actions
    func cycleStatus(for student: Student, modelContext: ModelContext) {
        guard let rec = recordsByStudent[student.id] else { return }
        let next = nextStatus(after: rec.status)
        let store = AttendanceStore(context: modelContext)
        if store.updateStatus(rec, to: next) {
            recordsByStudent[student.id]?.status = next
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
        guard let rec = recordsByStudent[student.id] else { return }
        let store = AttendanceStore(context: modelContext)
        if store.updateNote(rec, to: note) {
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            recordsByStudent[student.id]?.note = trimmed.isEmpty ? nil : trimmed
        }
    }

    func markAllPresent(students: [Student], modelContext: ModelContext) {
        let store = AttendanceStore(context: modelContext)
        do {
            let updated = try store.markAllPresent(for: selectedDate, students: students)
            let allowed = Set(students.map { $0.id })
            for rec in updated where allowed.contains(rec.studentID) {
                recordsByStudent[rec.studentID] = rec
            }
        } catch { }
    }

    func resetDay(students: [Student], modelContext: ModelContext) {
        let store = AttendanceStore(context: modelContext)
        do {
            let updated = try store.resetDay(for: selectedDate, students: students)
            let allowed = Set(students.map { $0.id })
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

