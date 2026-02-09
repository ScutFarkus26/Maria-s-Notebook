import Foundation
import SwiftData
import SwiftUI
import Combine
import OSLog

/// Handles the initial setup and database migrations for the app.
/// Moves heavy synchronous work off the main UI rendering flow of the App struct.
@MainActor
final class AppBootstrapper: ObservableObject {
    private static let logger = Logger.app(category: "Bootstrapper")

    enum State {
        case idle
        case initializingContainer
        case migrating
        case ready
    }
    
    @Published private(set) var state: State = .idle
    
    static let shared = AppBootstrapper()
    private init() {}
    
    func setState(_ newState: State) {
        state = newState
    }
    
    func bootstrap(modelContainer: ModelContainer) async {
        guard state == .idle else { return }
        state = .migrating
        
        let context = modelContainer.mainContext
        
        let startTime = Date()
        Self.logger.info("Bootstrap: Starting startup checks...")
        
        // 1. Calendar Setup
        let calendarStart = Date()
        AppCalendar.adopt(timeZoneFrom: Calendar.current)
        Self.logger.info("Bootstrap: Calendar setup completed in \(Self.formatSeconds(Date().timeIntervalSince(calendarStart)))s")
        
        // 1.5. Migrate lesson files to iCloud Drive (if needed)
        let filesMigrationStart = Date()
        if let migratedCount = LessonFileStorage.migrateToICloudDrive() {
            Self.logger.info("Bootstrap: Migrated \(migratedCount) lesson files to iCloud Drive in \(Self.formatSeconds(Date().timeIntervalSince(filesMigrationStart)))s")
        } else {
            Self.logger.info("Bootstrap: No lesson file migration needed")
        }
        
        // 2. Critical Data Repairs
        // (Completed and removed)
        
        // 3. Schema & Data Normalization (quick, safe checks)
        let migrationStart = Date()
        DataMigrations.fixCommunityTopicTagsIfNeeded(using: context)
        DataMigrations.fixStudentLessonStudentIDsIfNeeded(using: context)
        
        // 3.6. CloudKit compatibility: Migrate UUID foreign keys to Strings
        DataMigrations.migrateUUIDForeignKeysToStringsIfNeeded(using: context)
        DataMigrations.migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)
        
        // 3.6.5. GroupTrack default behavior migration: All groups are tracks by default (sequential)
        DataMigrations.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)
        Self.logger.info("Bootstrap: Quick migrations completed in \(Self.formatSeconds(Date().timeIntervalSince(migrationStart)))s")

        // 4. Initialize Reminder Sync Service
        let reminderStart = Date()
        ReminderSyncService.shared.modelContext = context
        // Perform initial sync if configured
        if ReminderSyncService.shared.syncListName != nil {
            Task {
                do {
                    try await ReminderSyncService.shared.syncReminders()
                    Self.logger.info("Bootstrap: Initial reminder sync completed")
                } catch {
                    Self.logger.error("Bootstrap: Initial reminder sync failed: \(error.localizedDescription)")
                }
            }
        }
        Self.logger.info("Bootstrap: Reminder service setup completed in \(Self.formatSeconds(Date().timeIntervalSince(reminderStart)))s")
        
        // 5. Signal UI (allow first render; heavy migrations continue in background)
        let routerStart = Date()
        AppRouter.shared.refreshPlanningInbox()
        Self.logger.info("Bootstrap: Router refresh completed in \(Self.formatSeconds(Date().timeIntervalSince(routerStart)))s")
        
        Self.logger.info("Bootstrap: Initial phase complete in \(Self.formatSeconds(Date().timeIntervalSince(startTime)))s - transitioning to ready state")
        state = .ready

        // 6. Run heavy migrations and dedup in the background to avoid UI stalls
        Task.detached(priority: .utility) { [modelContainer] in
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

        // 3.1. Schema & Data Normalization (potentially heavy)
        let normalizeStart = Date()
        await DataMigrations.normalizeGivenAtToDateOnlyIfNeeded(using: backgroundContext)
        logger.info("Post-launch migrations: normalizeGivenAt completed in \(formatSeconds(Date().timeIntervalSince(normalizeStart)))s")

        // 3.7. Legacy Backfill Migrations (one-time migrations)
        let backfillStart = Date()
        await DataMigrations.backfillRelationshipsIfNeeded(using: backgroundContext)
        await DataMigrations.backfillIsPresentedIfNeeded(using: backgroundContext)
        await DataMigrations.backfillScheduledForDayIfNeeded(using: backgroundContext)
        logger.info("Post-launch migrations: backfills completed in \(formatSeconds(Date().timeIntervalSince(backfillStart)))s")

        // 3.7.5. Repair incorrectly scoped notes
        let scopeRepairStart = Date()
        await DataMigrations.repairScopeForContextualNotes(using: backgroundContext)
        logger.info("Post-launch migrations: note scope repair completed in \(formatSeconds(Date().timeIntervalSince(scopeRepairStart)))s")

        // 3.8. Deduplication (CloudKit sync can create duplicates during merge conflicts)
        let dedupStart = Date()
        DataMigrations.deduplicateAllModels(using: backgroundContext)
        logger.info("Post-launch migrations: deduplication completed in \(formatSeconds(Date().timeIntervalSince(dedupStart)))s")

        // 3.9. Data Integrity Repairs (Run on ~10% of launches to reduce startup impact)
        if Int.random(in: 1...10) == 1 {
            let integrityStart = Date()
            await DataMigrations.repairDenormalizedScheduledForDay(using: backgroundContext)
            await DataMigrations.cleanOrphanedStudentIDs(using: backgroundContext)
            logger.info("Post-launch migrations: integrity repairs completed in \(formatSeconds(Date().timeIntervalSince(integrityStart)))s")
        }

        // 3.10. LessonAssignment Migration (StudentLesson + Presentation consolidation)
        let lessonAssignmentStart = Date()
        await DataMigrations.migrateLessonAssignmentsIfNeeded(using: backgroundContext)
        logger.info("Post-launch migrations: lesson assignment migration completed in \(formatSeconds(Date().timeIntervalSince(lessonAssignmentStart)))s")

        // Save all migration changes in one batch to minimize store coordinator changes
        do {
            try backgroundContext.save()
            logger.info("Post-launch migrations: saved all changes successfully")
        } catch {
            logger.error("Post-launch migrations: failed to save changes - \(error.localizedDescription)")
        }

        logger.info("Post-launch migrations finished in \(formatSeconds(Date().timeIntervalSince(start)))s")
    }

    private static func formatSeconds(_ interval: TimeInterval) -> String {
        String(format: "%.3f", interval)
    }
}
