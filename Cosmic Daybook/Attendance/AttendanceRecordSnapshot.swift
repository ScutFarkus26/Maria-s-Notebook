import Foundation
import CoreData

/// A record's mark as it stood before Reset Day cleared it, so the reset can
/// be undone: the status, reason and note, the times, and who made it.
struct AttendanceRecordSnapshot {
    let objectID: NSManagedObjectID
    let status: AttendanceStatus
    let absenceReason: AbsenceReason
    let note: String?
    let markedAt: Date?
    let leftAt: Date?
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
        recordedBy = record.recordedBy
        recordedByID = record.recordedByID
        recordedByName = record.recordedByName
    }

    /// Whether `record` holds nothing a reset would clear.
    static func isBlank(_ record: CDAttendanceRecord) -> Bool {
        record.status == .unmarked && record.absenceReason == .none && record.note == nil
    }

    /// Writes the snapshot back onto `record`. `modifiedAt` moves on, so the
    /// put-back mark wins over the reset on every device.
    func apply(to record: CDAttendanceRecord) {
        record.status = status
        record.absenceReason = absenceReason
        record.note = note
        record.markedAt = markedAt
        record.leftAt = leftAt
        record.recordedBy = recordedBy
        record.recordedByID = recordedByID
        record.recordedByName = recordedByName
        record.modifiedAt = Date()
    }
}
