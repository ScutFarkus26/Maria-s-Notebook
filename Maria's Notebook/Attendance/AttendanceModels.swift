import Foundation
import SwiftUI
import SwiftData

// MARK: - Attendance Status

enum AttendanceStatus: String, Codable, CaseIterable, Sendable {
    case unmarked
    case present
    case absent
    case tardy
    case leftEarly

    var displayName: String {
        switch self {
        case .unmarked: return "Unmarked"
        case .present: return "Present"
        case .absent: return "Absent"
        case .tardy: return "Tardy"
        case .leftEarly: return "Left Early"
        }
    }

    var color: Color {
        switch self {
        case .unmarked: return Color.gray.opacity(0.25)
        case .present: return Color.green.opacity(0.35)
        case .absent: return Color.red.opacity(0.35)
        case .tardy: return Color.blue.opacity(0.35)
        case .leftEarly: return Color.purple.opacity(0.35)
        }
    }
}

// MARK: - SwiftData Model

@Model
final class AttendanceRecord: Identifiable {
    // Persistent fields
    @Attribute(.unique) var id: UUID = UUID()
    var studentID: UUID = UUID()
    var date: Date = Date()          // normalized to start-of-day (local calendar)
    private var statusRaw: String = "unmarked"
    var note: String? = nil

    // Computed enum mapping for convenient UI usage
    var status: AttendanceStatus {
        get { AttendanceStatus(rawValue: statusRaw) ?? .unmarked }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        studentID: UUID,
        date: Date,
        status: AttendanceStatus = .unmarked,
        note: String? = nil
    ) {
        self.id = id
        self.studentID = studentID
        self.date = date
        self.statusRaw = status.rawValue
        self.note = note
    }
}

// MARK: - Date Normalization Helper

extension Date {
    /// Returns the start of the day for this date using the provided calendar (default .current).
    func normalizedDay(using calendar: Calendar = .current) -> Date {
        return calendar.startOfDay(for: self)
    }
}

// MARK: - Attendance Store (SwiftData Service)

/// A small service layer for fetching/upserting and updating attendance records.
struct AttendanceStore {
    let context: ModelContext
    var calendar: Calendar = .current

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // Fetch all records for a normalized date.
    private func fetchRecords(for normalizedDate: Date) throws -> [AttendanceRecord] {
        let descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate { $0.date == normalizedDate }
        )
        return try context.fetch(descriptor)
    }

    /// Loads all AttendanceRecords for the given date (normalized internally).
    /// For any students without a record, creates an unmarked record but does not save immediately.
    /// - Returns: The full set of records for the date, one per student, and a flag indicating if any inserts occurred.
    @discardableResult
    func loadOrCreateRecords(for date: Date, students: [Student]) throws -> (records: [AttendanceRecord], didInsert: Bool) {
        let day = date.normalizedDay(using: calendar)
        var existing = try fetchRecords(for: day)
        let existingByStudent = Dictionary(uniqueKeysWithValues: existing.map { ($0.studentID, $0) })

        var didInsert = false
        for student in students {
            if existingByStudent[student.id] == nil {
                let rec = AttendanceRecord(studentID: student.id, date: day, status: .unmarked, note: nil)
                context.insert(rec)
                existing.append(rec)
                didInsert = true
            }
        }
        return (existing, didInsert)
    }

    /// Update a record's status and return whether it changed.
    @discardableResult
    func updateStatus(_ record: AttendanceRecord, to newStatus: AttendanceStatus) -> Bool {
        let old = record.status
        record.status = newStatus
        return old != newStatus
    }

    /// Update a record's note and return whether it changed.
    @discardableResult
    func updateNote(_ record: AttendanceRecord, to newNote: String?) -> Bool {
        let trimmed = newNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newVal = (trimmed?.isEmpty == true) ? nil : trimmed
        let old = record.note
        record.note = newVal
        return old != newVal
    }

    /// Convenience: Mark all students present for the date, creating missing records.
    @discardableResult
    func markAllPresent(for date: Date, students: [Student]) throws -> [AttendanceRecord] {
        let result = try loadOrCreateRecords(for: date, students: students)
        for rec in result.records { rec.status = .present }
        return result.records
    }

    /// Convenience: Reset all to unmarked and clear notes for the date, creating missing records.
    @discardableResult
    func resetDay(for date: Date, students: [Student]) throws -> [AttendanceRecord] {
        let result = try loadOrCreateRecords(for: date, students: students)
        for rec in result.records { rec.status = .unmarked; rec.note = nil }
        return result.records
    }
}
