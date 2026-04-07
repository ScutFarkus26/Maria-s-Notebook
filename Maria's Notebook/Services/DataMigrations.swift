import Foundation
import CoreData
import OSLog

// MARK: - Data Migrations Facade

/// Central facade for data migrations.
/// Delegates to DataCleanupService for ongoing cleanup and deduplication.
enum DataMigrations {
    private static let logger = Logger.migration

    // MARK: - Data Cleanup (delegated to DataCleanupService)

    /// Remove all duplicate records across all model types.
    @discardableResult
    static func deduplicateAllModels(using context: NSManagedObjectContext) -> [String: Int] {
        DataCleanupService.deduplicateAllModels(using: context)
    }

    /// Deduplicate draft CDLessonAssignment records.
    static func deduplicateDraftLessonAssignments(using context: NSManagedObjectContext) {
        DataCleanupService.deduplicateDraftLessonAssignments(using: context)
    }

    /// Repairs denormalized scheduledForDay fields to match scheduledFor.
    static func repairDenormalizedScheduledForDay(using context: NSManagedObjectContext) async {
        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)
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

    /// Create NoteStudentLink records for existing notes with multi-student scope.
    static func createNoteStudentLinksForExistingNotes(using context: NSManagedObjectContext) {
        DataCleanupService.createNoteStudentLinksForExistingNotes(using: context)
    }

    /// Backfill scopeIsAll and searchIndexStudentID for notes that predate the search index.
    static func backfillNoteSearchIndex(using context: NSManagedObjectContext) {
        DataCleanupService.backfillNoteSearchIndex(using: context)
    }

    /// Backfill student/track relationships on enrollment records for CloudKit zone assignment.
    static func backfillTrackEnrollmentRelationships(using context: NSManagedObjectContext) {
        DataCleanupService.backfillTrackEnrollmentRelationships(using: context)
    }
}
