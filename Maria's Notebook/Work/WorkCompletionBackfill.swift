import Foundation
import CoreData

/// Utilities to migrate or mirror legacy completion flags (e.g., on participants)
/// into durable, historical `CDWorkCompletionRecord` entries.
enum WorkCompletionBackfill {
    /// Iterate through participants and ensure a corresponding
    /// `CDWorkCompletionRecord` exists for each participant that has `completedAt`.
    /// The operation is idempotent and safe to call multiple times.
    static func backfill(for workID: UUID, participants: [CDWorkParticipantEntity], in context: NSManagedObjectContext) throws {
        for p in participants {
            guard let completed = p.completedAt else { continue }
            guard let studentUUID = UUID(uuidString: p.studentID) else { continue }
            try ensureLatestRecord(
                for: workID, studentID: studentUUID,
                completedAt: completed,
                note: "(backfilled)", in: context
            )
        }
    }

    /// Ensure a record exists for an exact (workID, studentID, completedAt) triple.
    /// If not found, insert a new record with the provided note.
    @discardableResult
    static func ensureLatestRecord(
        for workID: UUID, studentID: UUID,
        completedAt: Date, note: String = "",
        in context: NSManagedObjectContext
    ) throws -> CDWorkCompletionRecord {
        let workIDString = workID.uuidString
        let studentIDString = studentID.uuidString
        let request = CDFetchRequest(CDWorkCompletionRecord.self)
        request.predicate = NSPredicate(
            format: "workID == %@ AND studentID == %@ AND completedAt == %@",
            workIDString, studentIDString, completedAt as NSDate
        )
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        let record = CDWorkCompletionRecord(context: context)
        record.workID = workIDString
        record.studentID = studentIDString
        record.completedAt = completedAt
        if !note.trimmed().isEmpty {
            record.setLegacyNoteText(note, in: context)
        }
        return record
    }
}
