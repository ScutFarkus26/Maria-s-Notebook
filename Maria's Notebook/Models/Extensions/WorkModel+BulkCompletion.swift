import Foundation
import SwiftData

extension WorkModel {
    /// Mark this work as completed for multiple students at once.
    /// Each student receives an individual historical record.
    /// Updates both WorkCompletionRecord (new system) and participant.completedAt (legacy system).
    @MainActor
    @discardableResult
    func markCompleted(for studentIDs: [UUID], note: String = "", at date: Date = Date(), in context: ModelContext) throws -> [WorkCompletionRecord] {
        var results: [WorkCompletionRecord] = []
        for id in studentIDs {
            // 1. Create WorkCompletionRecord (new system - preserves history)
            let rec = try WorkCompletionService.markCompleted(workID: self.id, studentID: id, note: note, at: date, in: context)
            results.append(rec)
            // 2. Update participant.completedAt (legacy system - for backwards compatibility)
            if let participant = self.participant(for: id) {
                participant.completedAt = date
            }
        }
        return results
    }
}
