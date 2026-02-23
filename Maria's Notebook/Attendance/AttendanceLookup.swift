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
    /// Handles duplicate records by keeping the first occurrence for each student ID.
    func attendanceStatuses(for studentIDs: [UUID], on date: Date) -> [UUID: AttendanceStatus] {
        guard !studentIDs.isEmpty else { return [:] }
        let day = date.normalizedDay()
        // CloudKit compatibility: Convert UUIDs to Strings for comparison
        let requestedStrings = Set(studentIDs.uuidStrings)
        let descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate { $0.date == day }
        )
        do {
            let recs: [AttendanceRecord] = try fetch(descriptor)
            // Build dictionary safely, handling potential duplicates by keeping the first occurrence
            var result: [UUID: AttendanceStatus] = [:]
            for rec in recs {
                guard requestedStrings.contains(rec.studentID),
                      let studentIDUUID = UUID(uuidString: rec.studentID),
                      result[studentIDUUID] == nil else { continue }
                result[studentIDUUID] = rec.status
            }
            return result
        } catch {
            return [:]
        }
    }
}
