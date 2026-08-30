import Foundation

// MARK: - CloudKit Duplicate Handling

/// The single ordering both dedup passes agree on, so the record the grid
/// shows, the record reports count, and the record the destructive cleanup
/// keeps are always the same one on every device.
enum AttendanceDeduplication {

    /// Whether `candidate` beats `incumbent` for the same (student, day):
    /// a marked record beats an unmarked one, then the latest `modifiedAt`
    /// wins (last writer, matching the CloudKit merge policy), then the
    /// lowest id string breaks the remaining tie deterministically.
    static func wins(_ candidate: CDAttendanceRecord, over incumbent: CDAttendanceRecord) -> Bool {
        let candidateMarked = candidate.status != .unmarked
        let incumbentMarked = incumbent.status != .unmarked
        if candidateMarked != incumbentMarked { return candidateMarked }
        let candidateModified = candidate.modifiedAt ?? .distantPast
        let incumbentModified = incumbent.modifiedAt ?? .distantPast
        if candidateModified != incumbentModified { return candidateModified > incumbentModified }
        return (candidate.id?.uuidString ?? "") < (incumbent.id?.uuidString ?? "")
    }
}

extension Array where Element == CDAttendanceRecord {
    /// Collapses CloudKit duplicates to one record per (student, day). Two devices
    /// marking the same day before syncing each create their own records; the grid
    /// only ever shows one status per student per day, so reports must count the
    /// same way. The winner is chosen by ``AttendanceDeduplication/wins(_:over:)``,
    /// so every device converges on the same record.
    func deduplicatedPerStudentDay() -> [CDAttendanceRecord] {
        var winners: [String: CDAttendanceRecord] = [:]
        for record in self {
            guard let date = record.date else { continue }
            let key = record.studentID + "|" + AppCalendar.dayID(date)
            if let incumbent = winners[key] {
                if AttendanceDeduplication.wins(record, over: incumbent) { winners[key] = record }
            } else {
                winners[key] = record
            }
        }
        return Array(winners.values)
    }
}
