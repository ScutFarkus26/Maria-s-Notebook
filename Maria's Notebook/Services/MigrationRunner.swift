import SwiftData
import Foundation

enum MigrationRunner {
    static func runIfNeeded(context: ModelContext) {
        let key = "MigrationRunner.v1.practiceFollowUpBackfill"
        // Disabled: Do not fetch or mutate WorkModel at startup.
        // Mark as done to avoid reruns while retaining compatibility flags.
        MigrationFlag.markComplete(key: key)
    }
}
