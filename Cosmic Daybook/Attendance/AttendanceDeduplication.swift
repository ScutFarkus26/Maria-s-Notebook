import Foundation

// MARK: - CloudKit Duplicate Handling

/// The single ordering both dedup passes agree on, so the record the grid
/// shows, the record reports count, and the record the destructive cleanup
/// keeps are always the same one on every device.
nonisolated enum AttendanceDeduplication {

    /// `absenceReasonRaw` on an absence Close Arrival made rather than a
    /// person. Not an `AbsenceReason` case: every reader, older builds
    /// included, sees no reason. A real mark or reason replaces it.
    static let automaticAbsenceRaw = "closeArrival"

    static func isAutomaticAbsence(_ record: CDAttendanceRecord) -> Bool {
        record.status == .absent && record.absenceReasonRaw == automaticAbsenceRaw
    }

    /// Whether `candidate` beats `incumbent` for the same (student, day):
    /// a marked record beats an unmarked one, then a real mark beats Close
    /// Arrival's automatic absence (the device that closed arrival hadn't
    /// seen the other mark), then the latest `modifiedAt` wins (last writer,
    /// matching the CloudKit merge policy), then the lowest id string
    /// breaks the remaining tie deterministically.
    static func wins(_ candidate: CDAttendanceRecord, over incumbent: CDAttendanceRecord) -> Bool {
        let candidateMarked = candidate.status != .unmarked
        let incumbentMarked = incumbent.status != .unmarked
        if candidateMarked != incumbentMarked { return candidateMarked }
        let candidateAutomatic = isAutomaticAbsence(candidate)
        let incumbentAutomatic = isAutomaticAbsence(incumbent)
        if candidateAutomatic != incumbentAutomatic { return incumbentAutomatic }
        let candidateModified = candidate.modifiedAt ?? .distantPast
        let incumbentModified = incumbent.modifiedAt ?? .distantPast
        if candidateModified != incumbentModified { return candidateModified > incumbentModified }
        return (candidate.id?.uuidString ?? "") < (incumbent.id?.uuidString ?? "")
    }
}

nonisolated extension Array where Element == CDAttendanceRecord {
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
