import Foundation
import CoreData

/// A small service layer that centralizes queries and mutations
/// around `CDWorkCompletionRecord`.
enum WorkCompletionService {
    // MARK: - Fetching

    /// Fetch all completion records for a given work ID.
    /// If `studentID` is provided, the results are filtered to that student.
    static func records(
        for workID: UUID, studentID: UUID? = nil,
        in context: NSManagedObjectContext
    ) throws -> [CDWorkCompletionRecord] {
        let request = CDFetchRequest(CDWorkCompletionRecord.self)
        let workIDString = workID.uuidString
        if let studentID {
            let studentIDString = studentID.uuidString
            request.predicate = NSPredicate(
                format: "workID == %@ AND studentID == %@",
                workIDString, studentIDString
            )
        } else {
            request.predicate = NSPredicate(format: "workID == %@", workIDString)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "completedAt", ascending: false)]
        return try context.fetch(request)
    }

    /// Fetch the latest (most recent) completion record for a given work + student.
    static func latest(for workID: UUID, studentID: UUID, in context: NSManagedObjectContext) throws -> CDWorkCompletionRecord? {
        try records(for: workID, studentID: studentID, in: context).first
    }

    /// Whether a student has at least one completion record for the given work.
    static func isCompleted(workID: UUID, studentID: UUID, in context: NSManagedObjectContext) throws -> Bool {
        let request = CDFetchRequest(CDWorkCompletionRecord.self)
        let workIDString = workID.uuidString
        let studentIDString = studentID.uuidString
        request.predicate = NSPredicate(
            format: "workID == %@ AND studentID == %@",
            workIDString, studentIDString
        )
        request.fetchLimit = 1
        return try !context.fetch(request).isEmpty
    }

    // MARK: - Mutations

    /// Record a completion event for a given work + student.
    /// This preserves history by appending a new record each time.
    @discardableResult
    static func markCompleted(
        workID: UUID, studentID: UUID,
        note: String = "", at date: Date = Date(),
        in context: NSManagedObjectContext
    ) throws -> CDWorkCompletionRecord {
        let record = CDWorkCompletionRecord(context: context)
        record.workID = workID.uuidString
        record.studentID = studentID.uuidString
        record.completedAt = date
        if !note.trimmed().isEmpty {
            record.setLegacyNoteText(note, in: context)
        }
        try context.save()
        return record
    }

    /// Convenience overload using instances if the caller has them.
    @discardableResult
    static func markCompleted(
        work: CDWorkModel, student: CDStudent,
        note: String = "", at date: Date = Date(),
        in context: NSManagedObjectContext
    ) throws -> CDWorkCompletionRecord {
        try markCompleted(
            workID: work.id ?? UUID(), studentID: student.id ?? UUID(),
            note: note, at: date, in: context
        )
    }

    // Deprecated ModelContext overloads removed - no longer needed with Core Data.
}
