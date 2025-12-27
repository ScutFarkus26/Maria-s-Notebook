import Foundation
import SwiftData

@available(*, deprecated, message: "Legacy WorkModel-based split logic has been retired. Calls are no-ops.")
enum WorkSplitService {
    @available(*, deprecated, message: "No-op: splitting legacy practice work is no longer supported.")
    static func splitPracticeWork(_ work: WorkModel, completedIDs: Set<UUID>, context: ModelContext) {
        // Intentionally no-op. Legacy WorkModel flow removed.
    }
}
