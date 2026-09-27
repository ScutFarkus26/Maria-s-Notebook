import Foundation
import CoreData
import SwiftUI
import OSLog

/// Handles the initial setup and database migrations for the app.
/// Moves heavy synchronous work off the main UI rendering flow of the App struct.
@Observable
final class AppBootstrapper {
    private static let logger = Logger.bootstrapper

    enum State {
        case idle
        case initializingContainer
        case migrating
        case ready
    }
    
    private(set) var state: State = .idle
    
    static let shared = AppBootstrapper()
    private init() {}
    
    func setState(_ newState: State) {
        state = newState
    }
    
    func bootstrap(coreDataStack: CoreDataStack) async {
        guard state == .idle else { return }
        state = .migrating

        let context = coreDataStack.viewContext

        let startTime = Date()
        let bootstrapInterval = LaunchSignposts.begin("Bootstrap")
        Self.logger.info("Bootstrap: Starting startup checks...")

        // Activate the iCloud ubiquity container in the background so the
        // "Cosmic Daybook" folder appears in Finder / Files.app at launch, and
        // keep its URL for the managed document folders, which read it from
        // then on instead of asking on the main thread (it is asked for again
        // whenever the iCloud identity changes; see UbiquityContainerCache).
        // Apple requires this call off the main thread; it can block briefly
        // while the container is set up for the first time.
        UbiquityContainerCache.shared.startRefreshing()

        let earlySetup = LaunchSignposts.begin("EarlySetup")
        performEarlySetup(context: context)
        LaunchSignposts.end("EarlySetup", earlySetup)

        // 4. Initialize CDReminder Sync Service (macOS only)
        #if os(macOS)
        let reminderStart = Date()
        ReminderSyncService.shared.managedObjectContext = context
        // Perform initial sync only if the user has configured a sync list in Settings.
        // No default list is seeded — sync stays off until explicitly configured.
        if ReminderSyncService.shared.syncListIdentifier != nil || ReminderSyncService.shared.syncListName != nil {
            Task {
                do {
                    try await ReminderSyncService.shared.syncReminders()
                    Self.logger.info("Bootstrap: Initial reminder sync completed")
                } catch let error as ReminderSyncError where error.isConfigurationIssue {
                    // Stale or missing configuration (e.g. the list was deleted in
                    // Reminders) — surfaced in Settings, not an app failure.
                    Self.logger.notice("Bootstrap: Initial reminder sync skipped: \(error.localizedDescription)")
                } catch {
                    Self.logger.error("Bootstrap: Initial reminder sync failed: \(error)")
                }
            }
        }
        let remElapsed = Self.formatSeconds(Date().timeIntervalSince(reminderStart))
        Self.logger.info("Bootstrap: Reminder setup completed in \(remElapsed)")
        #endif
        
        // 5. Signal UI (allow first render; heavy migrations continue in background)
        let routerStart = Date()
        AppRouter.shared.refreshPlanningInbox()
        let routerElapsed = Self.formatSeconds(Date().timeIntervalSince(routerStart))
        Self.logger.info("Bootstrap: Router refresh completed in \(routerElapsed)")
        
        let totalElapsed = Self.formatSeconds(Date().timeIntervalSince(startTime))
        Self.logger.info("Bootstrap: Initial phase complete in \(totalElapsed)")
        LaunchSignposts.end("Bootstrap", bootstrapInterval)
        state = .ready
        LaunchSignposts.event("UIReady")

        // 5.5. Initialize post-sync deduplication coordinator
        DeduplicationCoordinator.shared.persistentContainer = coreDataStack.container
        DeduplicationCoordinator.shared.coreDataStack = coreDataStack

        // 5.6. Start the shared-store orphan guard so any save that
        // inserts a shared-store entity either triggers auto-create of
        // the classroom CKShare (if none exists) or attaches the new
        // record to the existing share. Without this, runtime writes
        // would poison NSCloudKitMirroringDelegate (NSCocoaErrorDomain
        // 134060) between bootstrap and the next share-saved event.
        SharedStoreOrphanGuard.shared.start(coreDataStack: coreDataStack)

        // 6. Run heavy migrations and dedup in the background to avoid UI stalls
        // IMPORTANT: Delay background migrations to let the initial SwiftUI render complete.
        // Without this delay, background DB operations compete with @FetchRequest evaluations
        // and TodayViewModel.reload() for the persistent store coordinator, causing the
        // main thread to block in AG::Subgraph::update() (spinning beach ball).
        Task.detached(priority: .utility) { [coreDataStack] in
            try? await Task.sleep(for: .seconds(3))
            await AppBootstrapper.runPostLaunchMigrations(coreDataStack: coreDataStack)

            // Occasionally purge months-old persistent history that the CloudKit
            // mirroring delegate has provably exported (export-date gated; see
            // PersistentHistoryProcessor.purgeOldHistory for the safety rules).
            if let processor = await MainActor.run(body: { coreDataStack.historyProcessor }) {
                await processor.purgeOldHistory()
            }
        }
    }

    private func performEarlySetup(context: NSManagedObjectContext) {
        // Seed built-in templates (first launch or after restore)
        BuiltInTemplateSeeder.seedIfNeeded(context: context)
    }

    private static func runPostLaunchMigrations(coreDataStack: CoreDataStack) async {
        let start = Date()
        let migrations = LaunchSignposts.begin("PostLaunchMigrations")
        defer { LaunchSignposts.end("PostLaunchMigrations", migrations) }
        logger.info("Post-launch migrations started")

        // 3.8. Deduplication (CloudKit sync can create duplicates during merge
        // conflicts) runs later in this same sequence via MigrationRunner, on a
        // background context. It used to run here on the view context as well —
        // a second full pass over ~35 entity types whose results the view context
        // then held for the rest of the session.

        // The one-time steps that used to run around here (the May classroom
        // shared→private store move, the PDF folder move, two presentation
        // backfills, the March note-scope repair) were removed on 2026-09-26
        // once every device had long since run them.

        // 3.82. Ensure a CKShare exists for the classroom data so subsequent
        // shared-store writes can sync. The
        // actual container.share(_:to:) call is dispatched off the MainActor
        // and is gated by SharedStoreZoneRepair's circuit breaker so a
        // CloudKit timeout doesn't block launch.
        await ClassroomSharingService.ensureShareExistsOnLaunch(coreDataStack: coreDataStack)

        // 3.9. Data Integrity Repairs (Run on ~10% of launches to reduce startup impact).
        // They run first in MigrationRunner's background pass — the same place in
        // this sequence as before, but no longer on the view context.
        let includeIntegrityRepairs = Int.random(in: 1...10) == 1

        await MigrationRunner.runIfNeeded(
            coreDataStack: coreDataStack, includeIntegrityRepairs: includeIntegrityRepairs
        )

        // Drop the Claude/OpenAI API keys and model choices the Apple-only AI
        // change left on this device. Once per device; retried if the
        // Keychain refuses.
        RetiredAIKeysCleanup.runIfNeeded()

        // Save all migration changes in one batch to minimize store coordinator changes
        if coreDataStack.viewContext.hasChanges {
            if coreDataStack.viewContext.safeSave() {
                logger.info("Post-launch migrations: saved all changes successfully")
            }
        }

        // Shared-store zone repair runs LAST so it sees the final state
        // of the shared store, including any records written by the
        // migrations above. A record in the shared store without a
        // CKShare zone poisons the CloudKit mirroring delegate
        // (NSCocoaErrorDomain 134060) for the rest of the session.
        await SharedStoreZoneRepair.runIfNeeded(coreDataStack: coreDataStack)

        logger.info("Post-launch migrations finished in \(formatSeconds(Date().timeIntervalSince(start)))")

        // 4. Bring the full-text search index up to date after data is clean.
        // `refresh` reuses the on-disk snapshot and replays persistent history
        // since it was written; only a missing or stale snapshot costs a full pass.
        //
        // Skipped entirely on a hot device or in Low Power Mode: the refresh is
        // change-gated, so the next launch picks up everything this one missed.
        // Searching still works meanwhile — the snapshot on disk is just older.
        guard !EnergyPolicy.shared.shouldDeferMaintenance else {
            logger.notice("Post-launch: search index refresh skipped — device hot or in Low Power Mode")
            return
        }

        // 3.95. iCloud files. Photos kept on this device before note photos
        // moved to iCloud (2026-09-27) join them, once iCloud Drive is on; a
        // no-op once the local folder is empty. Then, on iPhone and iPad, ask
        // iCloud for every file of the app's not yet downloaded, so lesson
        // files, stories and photos open without a network.
        await PhotoStorageService.moveLocalPhotosToICloud()
        #if !os(macOS)
        UbiquitousDownloadSweep.shared.start()
        #endif
        let searchIndex = LaunchSignposts.begin("SearchIndexRebuild")
        await SearchIndexService.shared.refresh(container: coreDataStack.container)
        LaunchSignposts.end("SearchIndexRebuild", searchIndex)
    }

    private static func formatSeconds(_ interval: TimeInterval) -> String {
        interval.formattedAsDuration
    }
}
