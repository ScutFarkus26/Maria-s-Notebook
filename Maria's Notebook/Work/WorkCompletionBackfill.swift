import Foundation
import SwiftData

/// Utilities to migrate or mirror legacy completion flags (e.g., on participants)
/// into durable, historical `WorkCompletionRecord` entries.
enum WorkCompletionBackfill {
    /// Iterate through participants and ensure a corresponding
    /// `WorkCompletionRecord` exists for each participant that has `completedAt`.
    /// The operation is idempotent and safe to call multiple times.
    static func backfill(for workID: UUID, participants: [WorkParticipantEntity], in context: ModelContext) throws {
        for p in participants {
            guard let completed = p.completedAt else { continue }
            // CloudKit compatibility: Convert String studentID to UUID for the call
            guard let studentUUID = UUID(uuidString: p.studentID) else { continue }
            try ensureLatestRecord(for: workID, studentID: studentUUID, completedAt: completed, note: "(backfilled)", in: context)
        }
    }

    /// Ensure a record exists for an exact (workID, studentID, completedAt) triple.
    /// If not found, insert a new record with the provided note.
    @discardableResult
    static func ensureLatestRecord(for workID: UUID, studentID: UUID, completedAt: Date, note: String = "", in context: ModelContext) throws -> WorkCompletionRecord {
        // CloudKit compatibility: Convert UUIDs to strings for comparison
        let workIDString = workID.uuidString
        let studentIDString = studentID.uuidString
        var descriptor = FetchDescriptor<WorkCompletionRecord>(
            predicate: #Predicate { rec in
                rec.workID == workIDString && rec.studentID == studentIDString && rec.completedAt == completedAt
            }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let record = WorkCompletionRecord(workID: workID, studentID: studentID, completedAt: completedAt, note: note)
        context.insert(record)
        try context.save()
        return record
    }
}

