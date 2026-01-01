import Foundation
import SwiftData

// MARK: - Attendance Lookup Helpers

extension ModelContext {
    /// Returns the attendance status for a student on a specific date, if a record exists.
    /// The date is normalized to start-of-day for matching.
    func attendanceStatus(for studentID: UUID, on date: Date) -> AttendanceStatus? {
        let day = date.normalizedDay()
        // CloudKit compatibility: Convert UUID to String for comparison
        let studentIDString = studentID.uuidString
        var descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate { $0.studentID == studentIDString && $0.date == day }
        )
        descriptor.fetchLimit = 1
        do {
            let recs: [AttendanceRecord] = try fetch(descriptor)
            return recs.first?.status
        } catch {
            return nil
        }
    }

    /// Returns a dictionary of attendance statuses keyed by student ID for the given date.
    /// This performs a single fetch for the day and filters in-memory for the provided IDs.
    func attendanceStatuses(for studentIDs: [UUID], on date: Date) -> [UUID: AttendanceStatus] {
        guard !studentIDs.isEmpty else { return [:] }
        let day = date.normalizedDay()
        // CloudKit compatibility: Convert UUIDs to Strings for comparison
        let requestedStrings = Set(studentIDs.map { $0.uuidString })
        let descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate { $0.date == day }
        )
        do {
            let recs: [AttendanceRecord] = try fetch(descriptor)
            return Dictionary(uniqueKeysWithValues: recs.compactMap { rec in
                guard requestedStrings.contains(rec.studentID),
                      let studentIDUUID = UUID(uuidString: rec.studentID) else { return nil }
                return (studentIDUUID, rec.status)
            })
        } catch {
            return [:]
        }
    }
}
