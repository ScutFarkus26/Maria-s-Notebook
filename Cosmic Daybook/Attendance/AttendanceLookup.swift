import Foundation
import CoreData

// MARK: - Attendance Lookup Helpers

nonisolated extension NSManagedObjectContext {

    /// Returns a dictionary of attendance statuses keyed by student ID for the given date.
    /// This performs a single fetch for the day and filters in-memory for the provided IDs.
    /// CloudKit duplicates are resolved with the same deterministic winner the reports use,
    /// so the grid and the insights/report counts always agree.
    func attendanceStatuses(for studentIDs: [UUID], on date: Date) -> [UUID: AttendanceStatus] {
        guard !studentIDs.isEmpty else { return [:] }
        let day = date.normalizedDay()
        let requestedStrings = Set(studentIDs.uuidStrings)
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date == %@", day as NSDate)
        let recs = safeFetch(request).deduplicatedPerStudentDay()
        var result: [UUID: AttendanceStatus] = [:]
        for rec in recs {
            guard requestedStrings.contains(rec.studentID),
                  let studentIDUUID = UUID(uuidString: rec.studentID),
                  result[studentIDUUID] == nil else { continue }
            result[studentIDUUID] = rec.status
        }
        return result
    }

    /// `attendanceStatuses(for:on:)` for several days in one fetch.
    ///
    /// Each day asks about its own students, keyed by the day's
    /// `normalizedDay()`, and gets exactly what the single-day call returns:
    /// the records whose `date` is that day's start, CloudKit duplicates
    /// resolved per student and day with the same winner.
    func attendanceStatuses(
        forStudentsByDay studentsByDay: [Date: [UUID]]
    ) -> [Date: [UUID: AttendanceStatus]] {
        var requestedByDay: [Date: Set<String>] = [:]
        for (date, ids) in studentsByDay where !ids.isEmpty {
            requestedByDay[date.normalizedDay(), default: []].formUnion(ids.uuidStrings)
        }
        guard !requestedByDay.isEmpty else { return [:] }
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date IN %@", Array(requestedByDay.keys) as [NSDate])
        var result: [Date: [UUID: AttendanceStatus]] = [:]
        for rec in safeFetch(request).deduplicatedPerStudentDay() {
            guard let day = rec.date,
                  let requested = requestedByDay[day],
                  requested.contains(rec.studentID),
                  let studentIDUUID = UUID(uuidString: rec.studentID),
                  result[day]?[studentIDUUID] == nil else { continue }
            result[day, default: [:]][studentIDUUID] = rec.status
        }
        return result
    }
}
