import Foundation
import SwiftData
import SwiftUI
import Combine

/// Handles the initial setup and database migrations for the app.
/// Moves heavy synchronous work off the main UI rendering flow of the App struct.
@MainActor
final class AppBootstrapper: ObservableObject {
    enum State {
        case idle
        case migrating
        case ready
    }
    
    @Published private(set) var state: State = .idle
    
    static let shared = AppBootstrapper()
    private init() {}
    
    func bootstrap(modelContainer: ModelContainer) async {
        guard state == .idle else { return }
        state = .migrating
        
        let context = modelContainer.mainContext
        
        // print("AppBootstrapper: Starting startup checks...")
        
        // 1. Calendar Setup
        AppCalendar.adopt(timeZoneFrom: Calendar.current)
        
        // 2. Critical Data Repairs
        // (Completed and removed)
        
        // 3. Schema & Data Normalization (WorkModel logic disabled)
        await DataMigrations.normalizeGivenAtToDateOnlyIfNeeded(using: context)
        
        // 3.5. Fix type mismatches in stored array properties
        DataMigrations.fixCommunityTopicTagsIfNeeded(using: context)
        DataMigrations.fixStudentLessonStudentIDsIfNeeded(using: context)
        
        // 3.6. CloudKit compatibility: Migrate UUID foreign keys to Strings
        DataMigrations.migrateUUIDForeignKeysToStringsIfNeeded(using: context)
        DataMigrations.migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)
        
        // 3.6.5. GroupTrack default behavior migration: All groups are tracks by default (sequential)
        DataMigrations.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)

        // 3.7. Legacy Backfill Migrations (one-time migrations)
        // OPTIMIZATION: These are now async and yield periodically to avoid blocking UI
        await DataMigrations.backfillRelationshipsIfNeeded(using: context)
        await DataMigrations.backfillIsPresentedIfNeeded(using: context)
        await DataMigrations.backfillScheduledForDayIfNeeded(using: context)
        await DataMigrations.backfillPresentationStudentLessonLinks(using: context)
        await DataMigrations.repairPresentationStudentLessonLinks_v2(using: context)
        await DataMigrations.backfillNoteStudentLessonFromPresentation(using: context)
        
        // 3.7.5. Repair incorrectly scoped notes
        await DataMigrations.repairScopeForContextualNotes(using: context)
        
        // 3.8. Data Integrity Repairs (Run on ~10% of launches to reduce startup impact)
        if Int.random(in: 1...10) == 1 {
            await DataMigrations.repairDenormalizedScheduledForDay(using: context)
            await DataMigrations.cleanOrphanedStudentIDs(using: context)
        }
        
        // 4. Initialize Reminder Sync Service
        ReminderSyncService.shared.modelContext = context
        // Perform initial sync if configured
        if ReminderSyncService.shared.syncListName != nil {
            Task {
                do {
                    try await ReminderSyncService.shared.syncReminders()
                    // print("AppBootstrapper: Initial reminder sync completed")
                } catch {
                    // print("AppBootstrapper: Initial reminder sync failed: \(error.localizedDescription)")
                }
            }
        }
        
        // 5. Signal UI
        AppRouter.shared.refreshPlanningInbox()
        
        // print("AppBootstrapper: Startup checks complete.")
        state = .ready
    }
}
