import Foundation
import CoreData

/// Core Data service layer for fetching/upserting and updating attendance records.
struct CDAttendanceStore {
    let context: NSManagedObjectContext
    var calendar: Calendar = .current

    // Fetch all records for a normalized date.
    private func fetchRecords(for normalizedDate: Date) throws -> [CDAttendanceRecord] {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date == %@", normalizedDate as NSDate)
        return try context.fetch(request)
    }

    /// Loads all CDAttendanceRecords for the given date (normalized internally).
    /// For any students without a record, creates an unmarked record but does not save immediately.
    @discardableResult
    func loadOrCreateRecords(
        for date: Date,
        students: [CDStudent]
    ) throws -> (records: [CDAttendanceRecord], didInsert: Bool) {
        let day = date.normalizedDay(using: calendar)
        var existing = try fetchRecords(for: day)
        var existingByStudent: [String: CDAttendanceRecord] = [:]
        for record in existing {
            existingByStudent.insertIfAbsent(record, forKey: record.studentID)
        }

        var didInsert = false
        for student in students {
            let key = student.id?.uuidString ?? ""
            guard !key.isEmpty, existingByStudent[key] == nil else { continue }
            let rec = CDAttendanceRecord(context: context)
            rec.studentID = key
            rec.date = day
            rec.status = .unmarked
            rec.absenceReason = .none
            existing.append(rec)
            existingByStudent[key] = rec
            didInsert = true
        }
        return (existing, didInsert)
    }

    /// Update a record's status and return whether it changed.
    @discardableResult
    func updateStatus(_ record: CDAttendanceRecord, to newStatus: AttendanceStatus) -> Bool {
        let old = record.status
        record.status = newStatus
        return old != newStatus
    }

    /// Update a record's note and return whether it changed.
    @discardableResult
    func updateNote(_ record: CDAttendanceRecord, to newNote: String?) -> Bool {
        let trimmed = newNote?.trimmed()
        let newVal = (trimmed?.isEmpty == true) ? nil : trimmed
        return record.setLegacyNoteText(newVal, in: context)
    }

    /// Update a record's absence reason and return whether it changed.
    @discardableResult
    func updateAbsenceReason(_ record: CDAttendanceRecord, to newReason: AbsenceReason) -> Bool {
        guard record.status == .absent else { return false }
        let old = record.absenceReason
        record.absenceReason = newReason
        return old != newReason
    }

    /// Convenience: Mark all students present for the date, creating missing records.
    @discardableResult
    func markAllPresent(for date: Date, students: [CDStudent]) throws -> [CDAttendanceRecord] {
        let result = try loadOrCreateRecords(for: date, students: students)
        for rec in result.records { rec.status = .present }
        return result.records
    }

    /// Convenience: Reset all to unmarked and clear notes for the date, creating missing records.
    @discardableResult
    func resetDay(for date: Date, students: [CDStudent]) throws -> [CDAttendanceRecord] {
        let result = try loadOrCreateRecords(for: date, students: students)
        for rec in result.records {
            rec.status = .unmarked
            rec.setLegacyNoteText(nil, in: context)
            rec.absenceReason = .none
        }
        return result.records
    }
}
