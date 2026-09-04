import Foundation
import CoreData
import SwiftUI
import OSLog

/// Handles the initial setup and database migrations for the app.
/// Moves heavy synchronous work off the main UI rendering flow of the App struct.
@Observable
final class AppBootstrapper {
    private static let logger = Logger.app(category: "Bootstrapper")

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
        Self.logger.info("Bootstrap: Starting startup checks...")

        // Activate the iCloud ubiquity container in the background so the
        // "Montessori Daybook" folder appears in Finder / Files.app at launch.
        // Apple requires this call off the main thread; it can block briefly
        // while the container is set up for the first time.
        Task.detached(priority: .utility) {
            _ = FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }

        performEarlySetup(context: context)

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
        state = .ready

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
        let backgroundContext = coreDataStack.newBackgroundContext()
        
        let start = Date()
        logger.info("Post-launch migrations started")

        let log = logger
        await backgroundContext.perform {
            // 3.7.5. Repair incorrectly scoped notes
            // CDNote: repairScopeForContextualNotes is async+MainActor, call on main
            log.info("Post-launch: note scope repair starting")
        }

        await DataMigrations.repairScopeForContextualNotes(using: coreDataStack.viewContext)

        // 3.8. Deduplication (CloudKit sync can create duplicates during merge
        // conflicts) runs later in this same sequence via MigrationRunner, on a
        // background context. It used to run here on the view context as well —
        // a second full pass over ~35 entity types whose results the view context
        // then held for the rest of the session.

        // 3.81. Migrate classroom records (Students/Lessons/Tracks/…)
        // out of the .shared-scope shared store and into the .private-scope
        // private store. Earlier builds wrote them to the wrong store, which
        // makes container.share(_:to:) fail with NSCocoaErrorDomain 134060
        // ("objects must be in the correct destination store"). The
        // canonical NSPersistentCloudKitContainer sharing pattern requires
        // owner-side shareable data to live in the .private store; .shared
        // is only for data received from other users via accepted CKShares.
        // Idempotent + UserDefaults-gated; runs on a background context so
        // it doesn't block view fetches during launch.
        await ClassroomStoreMigration.runIfNeeded(coreDataStack: coreDataStack)

        // 3.82. Ensure a CKShare exists for the (now-properly-located)
        // classroom data so subsequent shared-store writes can sync. The
        // actual container.share(_:to:) call is dispatched off the MainActor
        // and is gated by SharedStoreZoneRepair's circuit breaker so a
        // CloudKit timeout doesn't block launch.
        await ClassroomSharingService.ensureShareExistsOnLaunch(coreDataStack: coreDataStack)

        // 3.85. Backfill per-student CDLessonPresentation rows for assignments that were marked
        // presented via entry points which historically skipped LifecycleService.recordPresentation.
        // Runs once per device (UserDefaults-guarded); idempotent.
        // Gated internally on SharedStoreZoneRepair.hasActiveShare.
        await MainActor.run {
            DataMigrations.backfillLessonPresentationsFromAssignments(using: coreDataStack.viewContext)
        }

        // 3.86. Link pre-fix work items to their lesson assignment. Work created by
        // the presentation workflow before the presentationID fix carries no link, so
        // required-practice gates could never see it complete and students stayed
        // blocked. Runs once per device (UserDefaults-guarded); idempotent.
        await MainActor.run {
            DataMigrations.backfillWorkPresentationLinks(using: coreDataStack.viewContext)
        }

        // 3.9. Data Integrity Repairs (Run on ~10% of launches to reduce startup impact)
        if Int.random(in: 1...10) == 1 {
            let integrityStart = Date()
            await DataMigrations.repairScheduledForDayMirror(using: coreDataStack.viewContext)
            await DataMigrations.cleanOrphanedStudentIDs(using: coreDataStack.viewContext)
            let intElapsed = formatSeconds(Date().timeIntervalSince(integrityStart))
            logger.info("Post-launch: integrity repairs completed in \(intElapsed)")
        }

        await MigrationRunner.runIfNeeded(coreDataStack: coreDataStack)

        await PDFFolderMigrationService.runIfNeeded(coreDataStack: coreDataStack)

        // Save all migration changes in one batch to minimize store coordinator changes
        await MainActor.run {
            if coreDataStack.viewContext.hasChanges {
                if coreDataStack.viewContext.safeSave() {
                    logger.info("Post-launch migrations: saved all changes successfully")
                }
            }
        }

        // Shared-store zone repair runs LAST so it sees the final state
        // of the shared store, including any records written by the
        // migrations above. A record in the shared store without a
        // CKShare zone poisons the CloudKit mirroring delegate
        // (NSCocoaErrorDomain 134060) for the rest of the session.
        await SharedStoreZoneRepair.runIfNeeded(coreDataStack: coreDataStack)

        logger.info("Post-launch migrations finished in \(formatSeconds(Date().timeIntervalSince(start)))")

        // 4. Build full-text search index after data is clean.
        // rebuildIndexAsync fetches on a background context so the main thread stays free.
        await SearchIndexService.shared.rebuildIndexAsync(container: coreDataStack.container)
    }

    private static func formatSeconds(_ interval: TimeInterval) -> String {
        interval.formattedAsDuration
    }
}
