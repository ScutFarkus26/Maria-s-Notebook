import Foundation
import CoreData
import OSLog

// MARK: - Data Migrations Facade

/// Central facade for data migrations.
/// Delegates to DataCleanupService for ongoing cleanup and deduplication.
nonisolated enum DataMigrations {
    private static let logger = Logger.migration

    // MARK: - Data Cleanup (delegated to DataCleanupService)

    /// Remove all duplicate records across all model types.
    /// Pass the CloudKit container when available so survivor selection is
    /// deterministic across devices (falls back to the CloudKit record name).
    @discardableResult
    static func deduplicateAllModels(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil
    ) -> [String: Int] {
        DataCleanupService.deduplicateAllModels(using: context, container: container)
    }

    /// Deduplicate draft CDLessonAssignment records.
    static func deduplicateDraftLessonAssignments(using context: NSManagedObjectContext) {
        DataCleanupService.deduplicateDraftLessonAssignments(using: context)
    }

    /// Normalizes lesson scheduling to the day-only model (snaps `scheduledFor` to
    /// Repairs the `scheduledForDay` mirror. Does not touch `scheduledFor`,
    /// which carries each lesson's position within its day.
    static func repairScheduledForDayMirror(using context: NSManagedObjectContext) async {
        await DataCleanupService.repairScheduledForDayMirror(using: context)
    }

    /// Cleans orphaned student IDs from CDLessonAssignment records.
    static func cleanOrphanedStudentIDs(using context: NSManagedObjectContext) async {
        await DataCleanupService.cleanOrphanedStudentIDs(using: context)
    }

    /// Cleans orphaned student IDs from CDWorkModel records.
    static func cleanOrphanedWorkStudentIDs(using context: NSManagedObjectContext) async {
        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)
    }

    /// Repair scope for notes that were incorrectly set to .all due to UI bugs.
    static func repairScopeForContextualNotes(using context: NSManagedObjectContext) async {
        await DataCleanupService.repairScopeForContextualNotes(using: context)
    }

    /// Clean up orphaned note images that are no longer referenced by any CDNote.
    static func cleanupOrphanedNoteImages(using context: NSManagedObjectContext) {
        DataCleanupService.cleanupOrphanedNoteImages(using: context)
    }

}
