import Foundation
import SwiftData
import CoreData
import OSLog

// MARK: - Data Migrations Facade

/// Central facade for all data migrations.
/// Delegates to specialized migration services for better organization and maintainability.
///
/// Migration services:
/// - `SchemaMigrationService`: Schema-level migrations (UUID to String, format changes)
/// - `RelationshipBackfillService`: Relationship backfilling between entities
/// - `DataCleanupService`: Orphaned data cleanup and deduplication
enum DataMigrations {
    private static let logger = Logger.migration

    // MARK: - Schema Migrations (delegated to SchemaMigrationService)

    /// Migrate AttendanceRecord.studentID from UUID to String format.
    static func migrateAttendanceRecordStudentIDToStringIfNeeded(using context: ModelContext) {
        SchemaMigrationService.migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)
    }

    /// Migrate GroupTrack records to include isExplicitlyDisabled field.
    static func migrateGroupTracksToDefaultBehaviorIfNeeded(using context: ModelContext) {
        SchemaMigrationService.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)
    }

    // MARK: - Data Cleanup (delegated to DataCleanupService)

    /// Remove all duplicate records across all model types.
    /// CloudKit sync can create duplicates during merge conflicts.
    /// Returns a dictionary of model type names to the number of duplicates removed.
    @discardableResult
    static func deduplicateAllModels(using context: ModelContext) -> [String: Int] {
        DataCleanupService.deduplicateAllModels(using: context)
    }

    /// Deduplicate draft LessonAssignment records.
    static func deduplicateDraftLessonAssignments(using context: ModelContext) {
        DataCleanupService.deduplicateDraftLessonAssignments(using: context)
    }

    /// Repairs denormalized scheduledForDay fields to match scheduledFor.
    static func repairDenormalizedScheduledForDay(using context: ModelContext) async {
        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)
    }

    /// Cleans orphaned student IDs from LessonAssignment records.
    static func cleanOrphanedStudentIDs(using context: ModelContext) async {
        await DataCleanupService.cleanOrphanedStudentIDs(using: context)
    }

    /// Cleans orphaned student IDs from WorkModel records.
    static func cleanOrphanedWorkStudentIDs(using context: ModelContext) async {
        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)
    }

    /// Repair scope for notes that were incorrectly set to .all due to UI bugs.
    static func repairScopeForContextualNotes(using context: ModelContext) async {
        await DataCleanupService.repairScopeForContextualNotes(using: context)
    }

    /// Clean up orphaned note images that are no longer referenced by any Note.
    static func cleanupOrphanedNoteImages(using context: ModelContext) {
        DataCleanupService.cleanupOrphanedNoteImages(using: context)
    }

    /// Create NoteStudentLink records for existing notes with multi-student scope.
    static func createNoteStudentLinksForExistingNotes(using context: ModelContext) {
        DataCleanupService.createNoteStudentLinksForExistingNotes(using: context)
    }

    // TODO: Remove after a few releases — backfills search index so scope getter no longer self-heals
    /// Backfill scopeIsAll and searchIndexStudentID for notes that predate the search index.
    static func backfillNoteSearchIndex(using context: ModelContext) {
        DataCleanupService.backfillNoteSearchIndex(using: context)
    }

    // MARK: - Relationship Backfills (delegated to RelationshipBackfillService)

    /// Backfill WorkCompletionRecord entries from existing WorkParticipantEntity.completedAt data.
    static func backfillWorkCompletionRecords(using context: ModelContext) {
        nonisolated(unsafe) let ctx = context
        MainActor.assumeIsolated {
            RelationshipBackfillService.backfillWorkCompletionRecords(using: ctx)
        }
    }

    /// Migrate WorkModel.workTypeRaw to WorkModel.kindRaw format.
    static func migrateWorkTypeToKind(using context: ModelContext) {
        nonisolated(unsafe) let ctx = context
        MainActor.assumeIsolated {
            RelationshipBackfillService.migrateWorkTypeToKind(using: ctx)
        }
    }
}
