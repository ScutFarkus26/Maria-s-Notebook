import CoreData
import Foundation
import OSLog

enum MigrationRunner {
    private static let logger = Logger.migration

    @MainActor static func runIfNeeded(coreDataStack: CoreDataStack) async {
        // Heavy, synchronous launch cleanup — deduplicating ~30 entity types and
        // sweeping orphaned note images — runs on a background context so it no
        // longer blocks the main thread during launch. The view context picks up
        // the results via `automaticallyMergesChangesFromParent`. This mirrors the
        // pattern already used by DeduplicationCoordinator for the post-sync pass.
        let bgContext = coreDataStack.newBackgroundContext()
        let container = coreDataStack.container
        let deduplicationResults: [String: Int] = await bgContext.perform {
            // Remove duplicate records that may have been created by CloudKit sync conflicts.
            let results = DataMigrations.deduplicateAllModels(using: bgContext, container: container)
            // Clean up any orphaned note images.
            DataMigrations.cleanupOrphanedNoteImages(using: bgContext)
            if bgContext.hasChanges {
                bgContext.safeSave()
            }
            return results
        }
        for (modelType, count) in deduplicationResults.sorted(by: { $0.key < $1.key }) {
            logger.info("Removed \(count, privacy: .public) duplicate \(modelType, privacy: .public) record(s)")
        }

        // Orphaned-work-student-ID cleanup yields cooperatively and accesses the
        // context directly (not via `perform`), so it must stay on the main-actor
        // view context where direct access is valid.
        await DataMigrations.cleanOrphanedWorkStudentIDs(using: coreDataStack.viewContext)
    }
}
