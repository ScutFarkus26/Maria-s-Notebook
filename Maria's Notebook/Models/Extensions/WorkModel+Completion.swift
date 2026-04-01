import Foundation
import CoreData

// WorkCompletionService is @MainActor, so we must isolate these convenience methods to MainActor as well.
@MainActor
extension CDWorkModel {
    /// Returns all completion records for this work (optionally filtered by student).
    func completionRecords(for studentID: UUID? = nil, in context: NSManagedObjectContext) throws -> [CDWorkCompletionRecord] {
        try WorkCompletionService.records(for: self.id ?? UUID(), studentID: studentID, in: context)
    }

    /// Returns the latest completion record for a given student.
    func latestCompletion(for studentID: UUID, in context: NSManagedObjectContext) throws -> CDWorkCompletionRecord? {
        try WorkCompletionService.latest(for: self.id ?? UUID(), studentID: studentID, in: context)
    }

    /// Whether the given student has completed this work at least once.
    func isCompleted(by studentID: UUID, in context: NSManagedObjectContext) throws -> Bool {
        try WorkCompletionService.isCompleted(workID: self.id ?? UUID(), studentID: studentID, in: context)
    }

    /// Mark this work as completed by a student. History is preserved.
    @discardableResult
    func markCompleted(
        by studentID: UUID,
        note: String = "",
        at date: Date = Date(),
        in context: NSManagedObjectContext
    ) throws -> CDWorkCompletionRecord {
        try WorkCompletionService.markCompleted(
            workID: self.id ?? UUID(),
            studentID: studentID,
            note: note,
            at: date,
            in: context
        )
    }

    /// Convenience overload using a `CDStudent` instance.
    @discardableResult
    func markCompleted(
        by student: CDStudent,
        note: String = "",
        at date: Date = Date(),
        in context: NSManagedObjectContext
    ) throws -> CDWorkCompletionRecord {
        try markCompleted(by: student.id ?? UUID(), note: note, at: date, in: context)
    }
}
