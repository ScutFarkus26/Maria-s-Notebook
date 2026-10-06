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
        /// The orphan-grace ledger after the pass, when one was passed in.
        var orphanGraceLedger: [String: Date]?
    }

    /// Runs the launch repairs on a background context.
    ///
    /// - Parameters:
    ///   - includeIntegrityRepairs: also run the whole-table `CDLessonAssignment`
    ///     repair (orphaned student IDs). The bootstrapper passes true on about
    ///     one launch in ten.
    ///   - lastImport: when a store last finished an import from iCloud, or nil
    ///     when none is known. The orphan graces (students, check-ins' missing
    ///     work) only act on an id once an import has finished since it went
    ///     missing; with nothing known, missing ids keep waiting.
    ///
    /// While the first download from iCloud is under way (`FirstDownloadGate`)
    /// the repairs that judge a row by what else is in the store — orphaned
    /// students, check-ins whose work is missing — wait: rows still on their
    /// way down would read as gone, and what they cleared would sync back up.
    static func runIfNeeded(
        coreDataStack: CoreDataStack,
        includeIntegrityRepairs: Bool = false,
        lastImport: @escaping @Sendable (ImportStoreKind) -> Date?
    ) async {
        // Heavy, synchronous launch cleanup — deduplicating ~30 entity types and
        // sweeping orphaned note images — runs on a background context so it no
        // longer blocks the main thread during launch. The view context picks up
        // the results via `automaticallyMergesChangesFromParent`. This mirrors the
        // pattern already used by DeduplicationCoordinator for the post-sync pass.
        let bgContext = coreDataStack.newBackgroundContext()
        let container = coreDataStack.container
        let firstDownloadPending = FirstDownloadGate.isPending()
        let noteScopeRepairDue = DataMigrations.noteScopeIndexRepairDue(firstDownloadPending: firstDownloadPending)
        // The post-import dedup waits while this pass runs (and this pass waits
        // for one already running): two passes on two contexts could each fold
        // the same rows from a view the other is changing.
        let outcome = await DeduplicationCoordinator.shared.holdingPasses {
            await runPass(
                on: bgContext,
                includeIntegrityRepairs: includeIntegrityRepairs,
                firstDownloadPending: firstDownloadPending,
                orphanGraceLedger: OrphanStudentGrace.load(from: .standard),
                lastImport: lastImport,
                sweep: { context in
                    launchSweep(
                        context,
                        container: container,
                        firstDownloadPending: firstDownloadPending,
                        noteScopeRepairDue: noteScopeRepairDue,
                        lastImport: lastImport
                    )
                }
            )
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
        if let ledger = outcome.orphanGraceLedger {
            OrphanStudentGrace.save(ledger, to: .standard)
        }
    }

    /// The launch pass's middle step: deduplication and the other launch
    /// cleanups, then one save. On `context`'s queue.
    nonisolated private static func launchSweep(
        _ context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer,
        firstDownloadPending: Bool,
        noteScopeRepairDue: Bool,
        lastImport: @escaping @Sendable (ImportStoreKind) -> Date?
    ) -> [String: Int] {
        // Remove duplicate records that may have been created by CloudKit sync conflicts.
        let results = DataMigrations.deduplicateAllModels(using: context, container: container)
        // Clean up any orphaned note images.
        DataMigrations.cleanupOrphanedNoteImages(using: context)
        // Check-ins that carry only a workID string, and whole-class notes
        // written on a presentation (see +CheckInAndNoteRepairs).
        DataMigrations.repairWorkCheckInLinks(
            using: context, firstDownloadPending: firstDownloadPending, lastImport: lastImport
        )
        // Notes saved with no scope blob join the whole-class index, once per
        // device (see +NoteScopeIndex); before the presentation-note repair, so
        // one on a presentation is narrowed to its roster in this same pass.
        if noteScopeRepairDue {
            DataMigrations.repairMissingNoteScopeIndex(using: context)
        }
        DataMigrations.repairPresentationNoteScopes(using: context)
        // Attendance notes kept as private Notes join their shared record.
        AttendanceNoteMove.run(using: context)
        // Rows still carrying the retired completion outcome (see +WorkStatusMerge).
        DataMigrations.mergeWorkCompletionOutcomes(using: context)
        // The check-in repair's first run counts only once what it did is saved.
        if !context.hasChanges || context.safeSave() {
            DataMigrations.markCheckInLinkRepairRun(firstDownloadPending: firstDownloadPending)
            if noteScopeRepairDue { DataMigrations.markNoteScopeIndexRepairDone() }
        }
        return results
    }

    /// Runs the launch repairs on `context`'s queue, in the order they have
    /// always run:
    /// 1. on `includeIntegrityRepairs` launches, orphaned student IDs on
    ///    assignments (until 2026-09-26 this ran just before this pass, on the
    ///    main-actor view context);
    /// 2. `sweep` — deduplication and the other launch cleanups, then a save;
    /// 3. orphaned student IDs on work rows (until 2026-09-26 this ran just
    ///    after the pass on the view context, firing one `participants` fault
    ///    per work row on the main thread).
    ///
    /// The scheduled-day mirror was rewritten in step 1 until 2026-10-05; it
    /// isn't any more (`DataMigrations.repairScheduledForDayMirror`).
    ///
    /// With `firstDownloadPending`, the two orphaned-student steps are skipped:
    /// the students they check against may not have downloaded yet.
    ///
    /// With `orphanGraceLedger`, a missing student id is only cleared once it has been
    /// missing on passes a day apart with an import since into the store that holds
    /// students (`OrphanStudentGrace`, `lastImport`); the updated ledger comes back in the
    /// outcome. Without one (tests), every missing id is cleared at once.
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
        firstDownloadPending: Bool,
        orphanGraceLedger: [String: Date]? = nil,
        lastImport: @escaping @Sendable (ImportStoreKind) -> Date? = { _ in nil },
        now: Date = Date(),
        sweep: @escaping @Sendable (NSManagedObjectContext) -> [String: Int]
    ) async -> PassOutcome {
        await context.perform {
            var outcome = PassOutcome()
            let grace = orphanGraceLedger.map { ledger in
                OrphanStudentGrace(ledger: ledger, now: now, lastImport: lastImport(studentStore(in: context)))
            }
            if includeIntegrityRepairs {
                let start = Date()
                if !firstDownloadPending {
                    DataMigrations.cleanOrphanedStudentIDs(using: context, grace: grace)
                    discardUnsavedChanges(in: context)
                }
                outcome.integrityRepairSeconds = Date().timeIntervalSince(start)
            }
            outcome.duplicatesRemoved = sweep(context)
            discardUnsavedChanges(in: context)
            if !firstDownloadPending {
                outcome.workRowsCleaned = DataMigrations.cleanOrphanedWorkStudentIDs(using: context, grace: grace)
                discardUnsavedChanges(in: context)
            }
            outcome.orphanGraceLedger = grace?.ledger
            return outcome
        }
    }

    /// Where this notebook's students live: the private store on the lead
    /// guide's devices (his own records, shared from there), the shared store
    /// on a notebook that joined someone else's classroom as an assistant.
    nonisolated private static func studentStore(in context: NSManagedObjectContext) -> ImportStoreKind {
        CDClassroomMembership.currentRole(in: context) == .assistant ? .sharedStore : .privateStore
    }

    /// Drops what a step left unsaved, which it only does when its save failed.
    nonisolated private static func discardUnsavedChanges(in context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        logger.error("A launch repair step could not save; discarding its changes before the next step")
        context.rollback()
    }
}
