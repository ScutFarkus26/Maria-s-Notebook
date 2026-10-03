import Foundation
import CoreData

/// A record's mark as it stood before Reset Day cleared it, or before a mark
/// changed it, so either can be undone: the status, reason and note, the
/// times (the pickup time too), and who made it.
///
/// Shared with the Daybook Assistant (compiled there by path): Siri's "Undo
/// that" keeps a snapshot's `values` between launches (`SiriAttendanceChange`).
struct AttendanceRecordSnapshot {
    let objectID: NSManagedObjectID
    let values: Values

    /// What the record held, apart from which record it is. The reason is
    /// kept as stored, so Close Arrival's automatic marker comes back too.
    nonisolated struct Values: Codable, Sendable {
        let status: AttendanceStatus
        let absenceReasonRaw: String
        let note: String?
        let markedAt: Date?
        let leftAt: Date?
        let leavesAt: Date?
        let returnedAt: Date?
        let statusBeforeLeavingRaw: String?
        let recordedBy: String?
        let recordedByID: String?
        let recordedByName: String?
    }

    init(_ record: CDAttendanceRecord) {
        objectID = record.objectID
        values = Values(
            status: record.status,
            absenceReasonRaw: record.absenceReasonRaw,
            note: record.note,
            markedAt: record.markedAt,
            leftAt: record.leftAt,
            leavesAt: record.leavesAt,
            returnedAt: record.returnedAt,
            statusBeforeLeavingRaw: record.statusBeforeLeavingRaw,
            recordedBy: record.recordedBy,
            recordedByID: record.recordedByID,
            recordedByName: record.recordedByName
        )
    }

    /// A snapshot kept apart from its record (Siri's), put back with it.
    init(objectID: NSManagedObjectID, values: Values) {
        self.objectID = objectID
        self.values = values
    }

    /// A record with nothing on it: what a child's first mark started from.
    init(blank objectID: NSManagedObjectID) {
        self.objectID = objectID
        values = Values(
            status: .unmarked,
            absenceReasonRaw: AbsenceReason.none.rawValue,
            note: nil,
            markedAt: nil,
            leftAt: nil,
            leavesAt: nil,
            returnedAt: nil,
            statusBeforeLeavingRaw: nil,
            recordedBy: nil,
            recordedByID: nil,
            recordedByName: nil
        )
    }

    /// Whether `record` still holds what the snapshot does: the mark, the
    /// reason, the note and the times a person sets.
    func matches(_ record: CDAttendanceRecord) -> Bool {
        record.status == values.status && record.absenceReasonRaw == values.absenceReasonRaw
            && record.note == values.note && record.leftAt == values.leftAt
            && record.leavesAt == values.leavesAt && record.returnedAt == values.returnedAt
    }

    /// Whether `record` holds nothing a reset would clear.
    static func isBlank(_ record: CDAttendanceRecord) -> Bool {
        record.status == .unmarked && record.absenceReason == .none && record.note == nil && record.leavesAt == nil
    }

    /// Writes the snapshot back onto `record`. `modifiedAt` moves on, so the
    /// put-back mark wins over the reset on every device.
    func apply(to record: CDAttendanceRecord) {
        record.status = values.status
        record.absenceReasonRaw = values.absenceReasonRaw
        record.note = values.note
        record.markedAt = values.markedAt
        record.leftAt = values.leftAt
        record.leavesAt = values.leavesAt
        record.returnedAt = values.returnedAt
        record.statusBeforeLeavingRaw = values.statusBeforeLeavingRaw
        record.recordedBy = values.recordedBy
        record.recordedByID = values.recordedByID
        record.recordedByName = values.recordedByName
        record.modifiedAt = Date()
    }
}
