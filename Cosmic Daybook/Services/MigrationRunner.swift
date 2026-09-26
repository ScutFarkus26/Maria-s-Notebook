import CoreData
import Foundation
import OSLog

enum MigrationRunner {
    nonisolated private static let logger = Logger.migration

    /// What one launch pass did, for the log.
    nonisolated struct PassOutcome: Sendable {
        /// Duplicates removed, per model type (what `sweep` returned).
        var duplicatesRemoved: [String: Int] = [:]
        /// How long the integrity repairs took, on launches that ran them.
        var integrityRepairSeconds: TimeInterval?
        /// Work rows whose orphaned student references were cleared.
        var workRowsCleaned = 0
    }

    /// Runs the launch repairs on a background context.
    ///
    /// - Parameter includeIntegrityRepairs: also run the two whole-table
    ///   `CDLessonAssignment` repairs (the scheduled-day mirror and orphaned
    ///   student IDs). The bootstrapper passes true on about one launch in ten.
    static func runIfNeeded(coreDataStack: CoreDataStack, includeIntegrityRepairs: Bool = false) async {
        // Heavy, synchronous launch cleanup — deduplicating ~30 entity types and
        // sweeping orphaned note images — runs on a background context so it no
        // longer blocks the main thread during launch. The view context picks up
        // the results via `automaticallyMergesChangesFromParent`. This mirrors the
        // pattern already used by DeduplicationCoordinator for the post-sync pass.
        let bgContext = coreDataStack.newBackgroundContext()
        let container = coreDataStack.container
        let outcome = await runPass(on: bgContext, includeIntegrityRepairs: includeIntegrityRepairs) { context in
            // Remove duplicate records that may have been created by CloudKit sync conflicts.
            let results = DataMigrations.deduplicateAllModels(using: context, container: container)
            // Clean up any orphaned note images.
            DataMigrations.cleanupOrphanedNoteImages(using: context)
            // Check-ins that carry only a workID string, and whole-class notes
            // written on a presentation (see +CheckInAndNoteRepairs).
            DataMigrations.repairWorkCheckInLinks(using: context)
            DataMigrations.repairPresentationNoteScopes(using: context)
            // Rows still carrying the retired completion outcome (see +WorkStatusMerge).
            DataMigrations.mergeWorkCompletionOutcomes(using: context)
            if context.hasChanges {
                context.safeSave()
            }
            return results
        }
        if let seconds = outcome.integrityRepairSeconds {
            logger.info("Post-launch: integrity repairs completed in \(seconds.formattedAsDuration)")
        }
        for (modelType, count) in outcome.duplicatesRemoved.sorted(by: { $0.key < $1.key }) {
            logger.info("Removed \(count, privacy: .public) duplicate \(modelType, privacy: .public) record(s)")
        }
        if outcome.workRowsCleaned > 0 {
            logger.info("Cleared orphaned students on \(outcome.workRowsCleaned, privacy: .public) work row(s)")
        }
    }

    /// Runs the launch repairs on `context`'s queue, in the order they have
    /// always run:
    /// 1. on `includeIntegrityRepairs` launches, the scheduled-day mirror and
    ///    orphaned student IDs on assignments (until 2026-09-26 these ran just
    ///    before this pass, on the main-actor view context);
    /// 2. `sweep` — deduplication and the other launch cleanups, then a save;
    /// 3. orphaned student IDs on work rows (until 2026-09-26 this ran just
    ///    after the pass on the view context, firing one `participants` fault
    ///    per work row on the main thread).
    ///
    /// Each step saves what it changed, as it did on its own context, so each
    /// reads what the one before saved — and the dedup's id-column pre-check,
    /// which falls back to reading whole tables on a context with unsaved
    /// changes, still starts clean. A step whose save failed leaves changes
    /// behind; they are dropped before the next step, which then reads the
    /// store as it did when the steps ran on separate contexts, so one failed
    /// save can't make every later save of the pass fail too.
    ///
    /// `@concurrent`, so the block is handed to the context from the calling
    /// task's executor at that task's priority (`.utility` at launch), not
    /// from the main thread.
    @concurrent
    nonisolated static func runPass(
        on context: NSManagedObjectContext,
        includeIntegrityRepairs: Bool,
        sweep: @escaping @Sendable (NSManagedObjectContext) -> [String: Int]
    ) async -> PassOutcome {
        await context.perform {
            var outcome = PassOutcome()
            if includeIntegrityRepairs {
                let start = Date()
                DataMigrations.repairScheduledForDayMirror(using: context)
                discardUnsavedChanges(in: context)
                DataMigrations.cleanOrphanedStudentIDs(using: context)
                discardUnsavedChanges(in: context)
                outcome.integrityRepairSeconds = Date().timeIntervalSince(start)
            }
            outcome.duplicatesRemoved = sweep(context)
            discardUnsavedChanges(in: context)
            outcome.workRowsCleaned = DataMigrations.cleanOrphanedWorkStudentIDs(using: context)
            discardUnsavedChanges(in: context)
            return outcome
        }
    }

    /// Drops what a step left unsaved, which it only does when its save failed.
    nonisolated private static func discardUnsavedChanges(in context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        logger.error("A launch repair step could not save; discarding its changes before the next step")
        context.rollback()
    }
}
