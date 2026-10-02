import Foundation
import CoreData

/// A record's mark as it stood before Reset Day cleared it, or before a mark
/// changed it, so either can be undone: the status, reason and note, the
/// times (the pickup time too), and who made it.
struct AttendanceRecordSnapshot {
    let objectID: NSManagedObjectID
    let status: AttendanceStatus
    let absenceReason: AbsenceReason
    let note: String?
    let markedAt: Date?
    let leftAt: Date?
    let leavesAt: Date?
    let returnedAt: Date?
    let statusBeforeLeavingRaw: String?
    let recordedBy: String?
    let recordedByID: String?
    let recordedByName: String?

    init(_ record: CDAttendanceRecord) {
        objectID = record.objectID
        status = record.status
        absenceReason = record.absenceReason
        note = record.note
        markedAt = record.markedAt
        leftAt = record.leftAt
        leavesAt = record.leavesAt
        returnedAt = record.returnedAt
        statusBeforeLeavingRaw = record.statusBeforeLeavingRaw
        recordedBy = record.recordedBy
        recordedByID = record.recordedByID
        recordedByName = record.recordedByName
    }

    /// A record with nothing on it: what a child's first mark started from.
    init(blank objectID: NSManagedObjectID) {
        self.objectID = objectID
        status = .unmarked
        absenceReason = .none
        note = nil
        markedAt = nil
        leftAt = nil
        leavesAt = nil
        returnedAt = nil
        statusBeforeLeavingRaw = nil
        recordedBy = nil
        recordedByID = nil
        recordedByName = nil
    }

    /// Whether `record` still holds what the snapshot does: the mark, the
    /// reason, the note and the times a person sets.
    func matches(_ record: CDAttendanceRecord) -> Bool {
        record.status == status && record.absenceReason == absenceReason && record.note == note
            && record.leftAt == leftAt && record.leavesAt == leavesAt && record.returnedAt == returnedAt
    }

    /// Whether `record` holds nothing a reset would clear.
    static func isBlank(_ record: CDAttendanceRecord) -> Bool {
        record.status == .unmarked && record.absenceReason == .none && record.note == nil && record.leavesAt == nil
    }

    /// Writes the snapshot back onto `record`. `modifiedAt` moves on, so the
    /// put-back mark wins over the reset on every device.
    func apply(to record: CDAttendanceRecord) {
        record.status = status
        record.absenceReason = absenceReason
        record.note = note
        record.markedAt = markedAt
        record.leftAt = leftAt
        record.leavesAt = leavesAt
        record.returnedAt = returnedAt
        record.statusBeforeLeavingRaw = statusBeforeLeavingRaw
        record.recordedBy = recordedBy
        record.recordedByID = recordedByID
        record.recordedByName = recordedByName
        record.modifiedAt = Date()
    }
}
