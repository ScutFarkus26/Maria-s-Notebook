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

    /// Whether `record` holds a mark, read from the raw value: a status a
    /// newer build added reads as unmarked through the typed `status`, and
    /// lost to a blank copy here (bug hunt 2026-10-05, #42).
    static func isMarked(_ record: CDAttendanceRecord) -> Bool {
        !record.statusRaw.isEmpty && record.statusRaw != AttendanceStatus.unmarked.rawValue
    }

    /// Whether `candidate` beats `incumbent` for the same (student, day):
    /// a marked record beats an unmarked one, then a real mark beats Close
    /// Arrival's automatic absence (the device that closed arrival hadn't
    /// seen the other mark), then the latest `modifiedAt` wins (last writer,
    /// matching the CloudKit merge policy), then the lowest id string
    /// breaks the remaining tie deterministically.
    static func wins(_ candidate: CDAttendanceRecord, over incumbent: CDAttendanceRecord) -> Bool {
        let candidateMarked = isMarked(candidate)
        let incumbentMarked = isMarked(incumbent)
        if candidateMarked != incumbentMarked { return candidateMarked }
        let candidateAutomatic = isAutomaticAbsence(candidate)
        let incumbentAutomatic = isAutomaticAbsence(incumbent)
        if candidateAutomatic != incumbentAutomatic { return incumbentAutomatic }
        let candidateModified = candidate.modifiedAt ?? .distantPast
        let incumbentModified = incumbent.modifiedAt ?? .distantPast
        if candidateModified != incumbentModified { return candidateModified > incumbentModified }
        return (candidate.id?.uuidString ?? "") < (incumbent.id?.uuidString ?? "")
    }

    // MARK: - Early pickups across duplicates

    /// The (student, day) a record belongs to, the key the read-side dedup
    /// groups by; nil for a record with no date.
    static func studentDayKey(_ record: CDAttendanceRecord) -> String? {
        guard let date = record.date else { return nil }
        return record.studentID + "|" + AppCalendar.dayID(date)
    }

    /// The pickup still planned for one child on one day, read across every
    /// record the day holds for them. The winner alone isn't enough: the
    /// guide sets a pickup ahead on an unmarked record, an assistant who
    /// hasn't seen it yet marks the child present on a record of her own,
    /// and the marked one wins (`wins(_:over:)`), so "leaves 1:30" and its
    /// reminder vanished. The grid, the Mac's roll and Today, the pickup
    /// reminders and the duplicate cleanup all read the time here.
    ///
    /// The latest pickup set (by `modifiedAt`) counts unless the day shows
    /// it done: its own record is marked Left Early (a pickup can't be set
    /// on a child already gone), or another copy says the child left early
    /// or came back (Back in Class, which clears the pickup on its own
    /// record) at or after the pickup was set. A pickup removed or replaced
    /// here is removed from every copy (`CDAttendanceStore.updateLeavesAt`),
    /// so a later clear leaves no older copy to bring it back.
    static func plannedPickup(among records: [CDAttendanceRecord]) -> Date? {
        let plans = records.filter { $0.leavesAt != nil }
        guard let plan = plans.max(by: { setEarlier($0, than: $1) }),
              let time = plan.leavesAt,
              plan.status != .leftEarly else { return nil }
        let setAt = plan.modifiedAt ?? .distantPast
        let done = records.contains { other in
            guard other !== plan, let at = endOfTrip(other) else { return false }
            return at >= setAt
        }
        return done ? nil : time
    }

    /// When `record` shows a child's early pickup over: when they left
    /// (Left Early), or came back (Back in Class: `returnedAt`, or, marked
    /// back on another day, the record's last change). Nil otherwise.
    private static func endOfTrip(_ record: CDAttendanceRecord) -> Date? {
        if record.status == .leftEarly { return record.leftAt ?? record.modifiedAt ?? .distantPast }
        if let back = record.returnedAt { return back }
        // Only Back in Class leaves a trip out on a present or late mark.
        if record.leftAt != nil, record.status == .present || record.status == .tardy {
            return record.modifiedAt ?? .distantPast
        }
        return nil
    }

    /// Whether `lhs`'s pickup was set before `rhs`'s: by `modifiedAt`, then
    /// the lowest id string counting as the later, so every device reads
    /// the same one.
    private static func setEarlier(_ lhs: CDAttendanceRecord, than rhs: CDAttendanceRecord) -> Bool {
        let lhsModified = lhs.modifiedAt ?? .distantPast
        let rhsModified = rhs.modifiedAt ?? .distantPast
        if lhsModified != rhsModified { return lhsModified < rhsModified }
        return (lhs.id?.uuidString ?? "") > (rhs.id?.uuidString ?? "")
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
            guard let key = AttendanceDeduplication.studentDayKey(record) else { continue }
            if let incumbent = winners[key] {
                if AttendanceDeduplication.wins(record, over: incumbent) { winners[key] = record }
            } else {
                winners[key] = record
            }
        }
        return Array(winners.values)
    }
}
