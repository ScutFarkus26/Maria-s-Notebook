import Foundation
import CoreData

// MARK: - Attendance Lookup Helpers

extension NSManagedObjectContext {

    /// Returns a dictionary of attendance statuses keyed by student ID for the given date.
    /// This performs a single fetch for the day and filters in-memory for the provided IDs.
    /// Handles duplicate records by keeping the first occurrence for each student ID.
    func attendanceStatuses(for studentIDs: [UUID], on date: Date) -> [UUID: AttendanceStatus] {
        guard !studentIDs.isEmpty else { return [:] }
        let day = date.normalizedDay()
        let requestedStrings = Set(studentIDs.uuidStrings)
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date == %@", day as NSDate)
        let recs = safeFetch(request)
        var result: [UUID: AttendanceStatus] = [:]
        for rec in recs {
            guard requestedStrings.contains(rec.studentID),
                  let studentIDUUID = UUID(uuidString: rec.studentID),
                  result[studentIDUUID] == nil else { continue }
            result[studentIDUUID] = rec.status
        }
        return result
    }
}

// Deprecated SwiftData ModelContext bridge methods removed.
