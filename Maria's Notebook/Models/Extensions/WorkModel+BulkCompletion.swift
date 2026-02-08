import Foundation
import SwiftData

extension WorkModel {
    /// Mark this work as completed for multiple students at once.
    /// Each student receives an individual historical record.
    @MainActor
    @discardableResult
    func markCompleted(for studentIDs: [UUID], note: String = "", at date: Date = Date(), in context: ModelContext) throws -> [WorkCompletionRecord] {
        var results: [WorkCompletionRecord] = []
        for id in studentIDs {
            let rec = try WorkCompletionService.markCompleted(workID: self.id, studentID: id, note: note, at: date, in: context)
            results.append(rec)
        }
        return results
    }
}
