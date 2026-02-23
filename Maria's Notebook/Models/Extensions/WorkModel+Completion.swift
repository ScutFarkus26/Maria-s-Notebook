import Foundation
import SwiftData

// WorkCompletionService is @MainActor, so we must isolate these convenience methods to MainActor as well.
@MainActor
extension WorkModel {
    /// Returns all completion records for this work (optionally filtered by student).
    func completionRecords(for studentID: UUID? = nil, in context: ModelContext) throws -> [WorkCompletionRecord] {
        try WorkCompletionService.records(for: self.id, studentID: studentID, in: context)
    }

    /// Returns the latest completion record for a given student.
    func latestCompletion(for studentID: UUID, in context: ModelContext) throws -> WorkCompletionRecord? {
        try WorkCompletionService.latest(for: self.id, studentID: studentID, in: context)
    }

    /// Whether the given student has completed this work at least once.
    func isCompleted(by studentID: UUID, in context: ModelContext) throws -> Bool {
        try WorkCompletionService.isCompleted(workID: self.id, studentID: studentID, in: context)
    }

    /// Mark this work as completed by a student. History is preserved.
    @discardableResult
    func markCompleted(by studentID: UUID, note: String = "", at date: Date = Date(), in context: ModelContext) throws -> WorkCompletionRecord {
        try WorkCompletionService.markCompleted(workID: self.id, studentID: studentID, note: note, at: date, in: context)
    }

    /// Convenience overload using a `Student` instance.
    @discardableResult
    func markCompleted(by student: Student, note: String = "", at date: Date = Date(), in context: ModelContext) throws -> WorkCompletionRecord {
        try markCompleted(by: student.id, note: note, at: date, in: context)
    }
}
