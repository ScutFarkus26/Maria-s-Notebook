import Foundation
import SwiftData

/// A small service layer that centralizes queries and mutations
/// around `WorkCompletionRecord`.
enum WorkCompletionService {
    // MARK: - Fetching

    /// Fetch all completion records for a given work ID.
    /// If `studentID` is provided, the results are filtered to that student.
    static func records(for workID: UUID, studentID: UUID? = nil, in context: ModelContext) throws -> [WorkCompletionRecord] {
        // CloudKit compatibility: Convert UUIDs to strings for comparison
        let workIDString = workID.uuidString
        if let studentID {
            let studentIDString = studentID.uuidString
            let descriptor = FetchDescriptor<WorkCompletionRecord>(
                predicate: #Predicate { $0.workID == workIDString && $0.studentID == studentIDString },
                sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
            )
            return try context.fetch(descriptor)
        } else {
            let descriptor = FetchDescriptor<WorkCompletionRecord>(
                predicate: #Predicate { $0.workID == workIDString },
                sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
            )
            return try context.fetch(descriptor)
        }
    }

    /// Fetch the latest (most recent) completion record for a given work + student.
    static func latest(for workID: UUID, studentID: UUID, in context: ModelContext) throws -> WorkCompletionRecord? {
        try records(for: workID, studentID: studentID, in: context).first
    }

    /// Whether a student has at least one completion record for the given work.
    static func isCompleted(workID: UUID, studentID: UUID, in context: ModelContext) throws -> Bool {
        // CloudKit compatibility: Convert UUIDs to strings for comparison
        let workIDString = workID.uuidString
        let studentIDString = studentID.uuidString
        var descriptor = FetchDescriptor<WorkCompletionRecord>(
            predicate: #Predicate { $0.workID == workIDString && $0.studentID == studentIDString }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty == false
    }

    // MARK: - Mutations

    /// Record a completion event for a given work + student.
    /// This preserves history by appending a new record each time.
    @discardableResult
    static func markCompleted(workID: UUID, studentID: UUID, note: String = "", at date: Date = Date(), in context: ModelContext) throws -> WorkCompletionRecord {
        let record = WorkCompletionRecord(
            workID: workID,
            studentID: studentID,
            completedAt: date,
            note: ""
        )
        context.insert(record)
        if !note.trimmed().isEmpty {
            _ = record.setLegacyNoteText(note, in: context)
        }
        try context.save()
        return record
    }

    /// Convenience overload using instances if the caller has them.
    @discardableResult
    static func markCompleted(work: WorkModel, student: Student, note: String = "", at date: Date = Date(), in context: ModelContext) throws -> WorkCompletionRecord {
        try markCompleted(workID: work.id, studentID: student.id, note: note, at: date, in: context)
    }
}

