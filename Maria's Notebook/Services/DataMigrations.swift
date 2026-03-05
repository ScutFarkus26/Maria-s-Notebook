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

    /// Legacy date normalization (no-op — model removed).
    static func normalizeGivenAtToDateOnlyIfNeeded(using context: ModelContext) async {
        await SchemaMigrationService.normalizeGivenAtToDateOnlyIfNeeded(using: context)
    }

    /// Migrate AttendanceRecord.studentID from UUID to String format.
    static func migrateAttendanceRecordStudentIDToStringIfNeeded(using context: ModelContext) {
        SchemaMigrationService.migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)
    }

    /// Migrate GroupTrack records to include isExplicitlyDisabled field.
    static func migrateGroupTracksToDefaultBehaviorIfNeeded(using context: ModelContext) {
        SchemaMigrationService.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)
    }

    /// Legacy WorkModel ID backfill (no-op — model removed).
    static func migrateWorkContractsToWorkModelsIfNeeded(using context: ModelContext) async {
        await SchemaMigrationService.migrateWorkContractsToWorkModelsIfNeeded(using: context)
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

    // MARK: - Relationship Backfills (delegated to RelationshipBackfillService)

    /// Legacy relationship backfill (no-op — model removed).
    static func backfillRelationshipsIfNeeded(using context: ModelContext) async {
        await RelationshipBackfillService.backfillRelationshipsIfNeeded(using: context)
    }

    /// Backfill WorkCompletionRecord entries from existing WorkParticipantEntity.completedAt data.
    /// This ensures all historical completion data is preserved in the WorkCompletionRecord system.
    /// Safe to run multiple times (idempotent).
    static func backfillWorkCompletionRecords(using context: ModelContext) {
        RelationshipBackfillService.backfillWorkCompletionRecords(using: context)
    }

    /// Migrate WorkModel.workTypeRaw to WorkModel.kindRaw format.
    /// This consolidates the dual type systems into a single WorkKind enum.
    /// Safe to run multiple times (idempotent).
    static func migrateWorkTypeToKind(using context: ModelContext) {
        RelationshipBackfillService.migrateWorkTypeToKind(using: context)
    }

    /// PHASE 6 COMPLETE: Legacy check-in migration methods removed.
    /// Legacy check-in model has been deleted and migration is complete.
    /// These methods are no longer available as the underlying model no longer exists.

    /// Legacy isPresented backfill (no-op — model removed).
    static func backfillIsPresentedIfNeeded(using context: ModelContext) async {
        await RelationshipBackfillService.backfillIsPresentedIfNeeded(using: context)
    }

    /// Legacy scheduledForDay backfill (no-op — model removed).
    static func backfillScheduledForDayIfNeeded(using context: ModelContext) async {
        await RelationshipBackfillService.backfillScheduledForDayIfNeeded(using: context)
    }

    // MARK: - LessonAssignment Migration (consolidation of legacy models)

    /// Legacy migration (no-op — model removed).
    /// Marks migration flags as complete.
    static func migrateLessonAssignmentsIfNeeded(using context: ModelContext) async {
        let service = LessonAssignmentMigrationService(context: context)
        do {
            _ = try await service.migrateIfNeeded()
        } catch {
            logger.warning("Failed to migrate lesson assignments: \(error.localizedDescription)")
        }
    }

    /// Re-run the LessonAssignment migration to catch records created after the v1 migration.
    static func migrateLessonAssignmentsV2IfNeeded(using context: ModelContext) async {
        let service = LessonAssignmentMigrationService(context: context)
        do {
            _ = try await service.migrateIfNeededV2()
        } catch {
            logger.warning("Failed to run v2 lesson assignment migration: \(error.localizedDescription)")
        }
    }

    /// Validates that the LessonAssignment migration completed successfully.
    /// Returns the validation result for logging/debugging purposes.
    static func validateLessonAssignmentMigration(using context: ModelContext) async -> LessonAssignmentValidationResult? {
        let validator = LessonAssignmentMigrationValidator(context: context)
        do {
            return try await validator.validate()
        } catch {
            logger.warning("Failed to validate lesson assignment migration: \(error.localizedDescription)")
            return nil
        }
    }
}
