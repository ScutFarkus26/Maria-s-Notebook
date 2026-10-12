import Foundation
import CoreData

/// Writes `CDWorkCompletionRecord`s.
enum WorkCompletionService {
    /// Record a completion event for a given work + student.
    /// This preserves history by appending a new record each time.
    /// `saveImmediately: false` lets a caller that writes several things
    /// (`WorkLogService`) save once at the end.
    @discardableResult
    static func markCompleted(
        workID: UUID, studentID: UUID,
        note: String = "", at date: Date = Date(),
        in context: NSManagedObjectContext,
        saveImmediately: Bool = true
    ) throws -> CDWorkCompletionRecord {
        let record = CDWorkCompletionRecord(context: context)
        record.workID = workID.uuidString
        record.studentID = studentID.uuidString
        record.completedAt = date
        if !note.trimmed().isEmpty {
            record.setLegacyNoteText(note, in: context)
        }
        if saveImmediately {
            try context.save()
        }
        return record
    }

}
