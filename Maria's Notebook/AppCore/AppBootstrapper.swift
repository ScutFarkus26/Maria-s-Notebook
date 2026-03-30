import Foundation
import SwiftData
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

        // Legacy ModelContainer + context still used by services not yet converted to Core Data.
        // Will be replaced with coreDataStack.viewContext in Phase 3.
        let modelContainer = AppBootstrapping.getSharedModelContainer()
        let context = modelContainer.mainContext
        
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
        ReminderSyncService.shared.modelContext = context
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
        DeduplicationCoordinator.shared.modelContainer = modelContainer

        // 6. Run heavy migrations and dedup in the background to avoid UI stalls
        // IMPORTANT: Delay background migrations to let the initial SwiftUI render complete.
        // Without this delay, background DB operations compete with @Query evaluations
        // and TodayViewModel.reload() for the persistent store coordinator, causing the
        // main thread to block in AG::Subgraph::update() (spinning beach ball).
        Task.detached(priority: .utility) { [modelContainer] in
            try? await Task.sleep(for: .seconds(3))
            await AppBootstrapper.runPostLaunchMigrations(modelContainer: modelContainer)
        }
    }

    private static func runPostLaunchMigrations(modelContainer: ModelContainer) async {
        let backgroundContext = ModelContext(modelContainer)
        
        // Disable autosave to prevent triggering CloudKit sync during heavy migrations
        // This reduces store coordinator changes that can tear down the CloudKit delegate
        backgroundContext.autosaveEnabled = false
        
        let start = Date()
        logger.info("Post-launch migrations started")

        // 3.7.5. Repair incorrectly scoped notes
        let scopeRepairStart = Date()
        await DataMigrations.repairScopeForContextualNotes(using: backgroundContext)
        let scopeElapsed = formatSeconds(Date().timeIntervalSince(scopeRepairStart))
        logger.info("Post-launch: note scope repair completed in \(scopeElapsed)")

        // 3.8. Deduplication (CloudKit sync can create duplicates during merge conflicts)
        let dedupStart = Date()
        DataMigrations.deduplicateAllModels(using: backgroundContext)
        let dedupElapsed = formatSeconds(Date().timeIntervalSince(dedupStart))
        logger.info("Post-launch: deduplication completed in \(dedupElapsed)")

        // 3.9. Data Integrity Repairs (Run on ~10% of launches to reduce startup impact)
        if Int.random(in: 1...10) == 1 {
            let integrityStart = Date()
            await DataMigrations.repairDenormalizedScheduledForDay(using: backgroundContext)
            await DataMigrations.cleanOrphanedStudentIDs(using: backgroundContext)
            let intElapsed = formatSeconds(Date().timeIntervalSince(integrityStart))
            logger.info("Post-launch: integrity repairs completed in \(intElapsed)")
        }

        await MigrationRunner.runIfNeeded(context: backgroundContext)

        // Save all migration changes in one batch to minimize store coordinator changes
        do {
            try backgroundContext.save()
            logger.info("Post-launch migrations: saved all changes successfully")
        } catch {
            logger.error("Post-launch migrations: failed to save changes - \(error.localizedDescription)")
        }

        logger.info("Post-launch migrations finished in \(formatSeconds(Date().timeIntervalSince(start)))")

        // 4. Build full-text search index after data is clean
        await MainActor.run {
            SearchIndexService.shared.rebuildIndex(container: modelContainer)
        }
    }

    private static func formatSeconds(_ interval: TimeInterval) -> String {
        interval.formattedAsDuration
    }
}
