import SwiftData
import Foundation

enum MigrationRunner {
    static func runIfNeeded(context: ModelContext) async {
        let key = "MigrationRunner.v1.practiceFollowUpBackfill"
        // Disabled: Do not fetch or mutate WorkModel at startup.
        // Mark as done to avoid reruns while retaining compatibility flags.
        MigrationFlag.markComplete(key: key)

        // Migrate legacy string notes on WorkModels to Note objects
        Task { @MainActor in
            DataMigrations.migrateLegacyWorkNotesToNoteObjects(using: context)
        }

        // Clean orphaned student IDs from WorkModel records
        await DataMigrations.cleanOrphanedWorkStudentIDs(using: context)
    }
}
