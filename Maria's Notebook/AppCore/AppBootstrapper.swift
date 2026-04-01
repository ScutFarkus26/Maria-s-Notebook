import Foundation
import CoreData
import SwiftUI
import OSLog

/// Handles the initial setup and database migrations for the app.
/// Moves heavy synchronous work off the main UI rendering flow of the App struct.
@Observable
@MainActor
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
        
        // 1. Calendar Setup
        let calendarStart = Date()
        AppCalendar.adopt(timeZoneFrom: Calendar.current)
        let calElapsed = Self.formatSeconds(Date().timeIntervalSince(calendarStart))
        Self.logger.info("Bootstrap: Calendar setup completed in \(calElapsed)")
        
        // 1.5. Migrate lesson files to iCloud Drive (if needed)
        let filesMigrationStart = Date()
        if let migratedCount = LessonFileStorage.migrateToICloudDrive() {
            let filesElapsed = Self.formatSeconds(Date().timeIntervalSince(filesMigrationStart))
            Self.logger.info("Bootstrap: Migrated \(migratedCount) files in \(filesElapsed)")
        } else {
            Self.logger.info("Bootstrap: No lesson file migration needed")
        }
        
        // 2. Critical Data Repairs
        // (Completed and removed)
        
        // 3. Schema & Data Normalization (quick, safe checks)
        let migrationStart = Date()
        DataMigrations.migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)
        
        // 3.6.5. GroupTrack default behavior migration
        DataMigrations.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)
        let migElapsed = Self.formatSeconds(Date().timeIntervalSince(migrationStart))
        Self.logger.info("Bootstrap: Quick migrations completed in \(migElapsed)")

        // 4. Initialize Reminder Sync Service (macOS only)
        #if os(macOS)
        let reminderStart = Date()
        ReminderSyncService.shared.managedObjectContext = context
        // Set default reminder list if none configured
        if ReminderSyncService.shared.syncListName == nil && ReminderSyncService.shared.syncListIdentifier == nil {
            ReminderSyncService.shared.syncListName = "girls class reminders"
        }
        // Perform initial sync if configured
        if ReminderSyncService.shared.syncListName != nil {
            Task {
                do {
                    try await ReminderSyncService.shared.syncReminders()
                    Self.logger.info("Bootstrap: Initial reminder sync completed")
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

        // 6. Run heavy migrations and dedup in the background to avoid UI stalls
        // IMPORTANT: Delay background migrations to let the initial SwiftUI render complete.
        // Without this delay, background DB operations compete with @FetchRequest evaluations
        // and TodayViewModel.reload() for the persistent store coordinator, causing the
        // main thread to block in AG::Subgraph::update() (spinning beach ball).
        Task.detached(priority: .utility) { [coreDataStack] in
            try? await Task.sleep(for: .seconds(3))
            await AppBootstrapper.runPostLaunchMigrations(coreDataStack: coreDataStack)

            // Purge persistent history before last processed token
            if let processor = await MainActor.run(body: { coreDataStack.historyProcessor }) {
                await processor.purgeOldHistory()
            }
        }
    }

    private static func runPostLaunchMigrations(coreDataStack: CoreDataStack) async {
        let backgroundContext = await coreDataStack.newBackgroundContext()
        
        let start = Date()
        logger.info("Post-launch migrations started")

        await backgroundContext.perform {
            // 3.7.5. Repair incorrectly scoped notes
            let scopeRepairStart = Date()
            // Note: repairScopeForContextualNotes is async+MainActor, call on main
            logger.info("Post-launch: note scope repair starting")
        }

        await DataMigrations.repairScopeForContextualNotes(using: await coreDataStack.viewContext)

        let dedupStart = Date()
        await MainActor.run {
            // 3.8. Deduplication (CloudKit sync can create duplicates during merge conflicts)
            DataMigrations.deduplicateAllModels(using: coreDataStack.viewContext)
        }
        logger.info("Post-launch: deduplication completed in \(formatSeconds(Date().timeIntervalSince(dedupStart)))")

        // 3.9. Data Integrity Repairs (Run on ~10% of launches to reduce startup impact)
        if Int.random(in: 1...10) == 1 {
            let integrityStart = Date()
            await DataMigrations.repairDenormalizedScheduledForDay(using: await coreDataStack.viewContext)
            await DataMigrations.cleanOrphanedStudentIDs(using: await coreDataStack.viewContext)
            logger.info("Post-launch: integrity repairs completed in \(formatSeconds(Date().timeIntervalSince(integrityStart)))")
        }

        await MigrationRunner.runIfNeeded(context: await coreDataStack.viewContext)

        // Save all migration changes in one batch to minimize store coordinator changes
        await MainActor.run {
            if coreDataStack.viewContext.hasChanges {
                do {
                    try coreDataStack.viewContext.save()
                    logger.info("Post-launch migrations: saved all changes successfully")
                } catch {
                    logger.error("Post-launch migrations: failed to save changes - \(error.localizedDescription)")
                }
            }
        }

        logger.info("Post-launch migrations finished in \(formatSeconds(Date().timeIntervalSince(start)))")

        // 4. Build full-text search index after data is clean
        await MainActor.run {
            SearchIndexService.shared.rebuildIndex(context: coreDataStack.viewContext)
        }
    }

    private static func formatSeconds(_ interval: TimeInterval) -> String {
        interval.formattedAsDuration
    }
}
