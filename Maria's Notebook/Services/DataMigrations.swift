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
    static func migrateAttendanceRecordStudentIDToStringIfNeeded(using context: NSManagedObjectContext) {
        SchemaMigrationService.migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)
    }

    /// Migrate GroupTrack records to include isExplicitlyDisabled field.
    static func migrateGroupTracksToDefaultBehaviorIfNeeded(using context: NSManagedObjectContext) {
        SchemaMigrationService.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)
    }

    // MARK: - Data Cleanup (delegated to DataCleanupService)

    /// Remove all duplicate records across all model types.
    @discardableResult
    static func deduplicateAllModels(using context: NSManagedObjectContext) -> [String: Int] {
        DataCleanupService.deduplicateAllModels(using: context)
    }

    /// Deduplicate draft LessonAssignment records.
    static func deduplicateDraftLessonAssignments(using context: NSManagedObjectContext) {
        DataCleanupService.deduplicateDraftLessonAssignments(using: context)
    }

    /// Repairs denormalized scheduledForDay fields to match scheduledFor.
    static func repairDenormalizedScheduledForDay(using context: NSManagedObjectContext) async {
        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)
    }

    /// Cleans orphaned student IDs from LessonAssignment records.
    static func cleanOrphanedStudentIDs(using context: NSManagedObjectContext) async {
        await DataCleanupService.cleanOrphanedStudentIDs(using: context)
    }

    /// Cleans orphaned student IDs from WorkModel records.
    static func cleanOrphanedWorkStudentIDs(using context: NSManagedObjectContext) async {
        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)
    }

    /// Repair scope for notes that were incorrectly set to .all due to UI bugs.
    static func repairScopeForContextualNotes(using context: NSManagedObjectContext) async {
        await DataCleanupService.repairScopeForContextualNotes(using: context)
    }

    /// Clean up orphaned note images that are no longer referenced by any Note.
    static func cleanupOrphanedNoteImages(using context: NSManagedObjectContext) {
        DataCleanupService.cleanupOrphanedNoteImages(using: context)
    }

    /// Create NoteStudentLink records for existing notes with multi-student scope.
    static func createNoteStudentLinksForExistingNotes(using context: NSManagedObjectContext) {
        DataCleanupService.createNoteStudentLinksForExistingNotes(using: context)
    }

    // TODO: Remove after a few releases — backfills search index so scope getter no longer self-heals
    /// Backfill scopeIsAll and searchIndexStudentID for notes that predate the search index.
    static func backfillNoteSearchIndex(using context: NSManagedObjectContext) {
        DataCleanupService.backfillNoteSearchIndex(using: context)
    }

    // MARK: - Relationship Backfills (delegated to RelationshipBackfillService)

    /// Backfill WorkCompletionRecord entries from existing WorkParticipantEntity.completedAt data.
    @MainActor
    static func backfillWorkCompletionRecords(using context: NSManagedObjectContext) {
        RelationshipBackfillService.backfillWorkCompletionRecords(using: context)
    }

    /// Migrate WorkModel.workTypeRaw to WorkModel.kindRaw format.
    @MainActor
    static func migrateWorkTypeToKind(using context: NSManagedObjectContext) {
        RelationshipBackfillService.migrateWorkTypeToKind(using: context)
    }

    // MARK: - Deprecated ModelContext Bridges

    /// Helper to get the CD view context from within a nonisolated deprecated bridge.
    /// Callers must be on the main thread (migration runner, view callbacks).
    private static var cdViewContext: NSManagedObjectContext {
        MainActor.assumeIsolated {
            AppBootstrapping.getSharedCoreDataStack().viewContext
        }
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func migrateAttendanceRecordStudentIDToStringIfNeeded(using context: ModelContext) {
        migrateAttendanceRecordStudentIDToStringIfNeeded(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func migrateGroupTracksToDefaultBehaviorIfNeeded(using context: ModelContext) {
        migrateGroupTracksToDefaultBehaviorIfNeeded(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    @discardableResult
    static func deduplicateAllModels(using context: ModelContext) -> [String: Int] {
        deduplicateAllModels(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func deduplicateDraftLessonAssignments(using context: ModelContext) {
        deduplicateDraftLessonAssignments(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func repairDenormalizedScheduledForDay(using context: ModelContext) async {
        await repairDenormalizedScheduledForDay(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func cleanOrphanedStudentIDs(using context: ModelContext) async {
        await cleanOrphanedStudentIDs(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func cleanOrphanedWorkStudentIDs(using context: ModelContext) async {
        await cleanOrphanedWorkStudentIDs(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func repairScopeForContextualNotes(using context: ModelContext) async {
        await repairScopeForContextualNotes(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func cleanupOrphanedNoteImages(using context: ModelContext) {
        cleanupOrphanedNoteImages(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func createNoteStudentLinksForExistingNotes(using context: ModelContext) {
        createNoteStudentLinksForExistingNotes(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func backfillNoteSearchIndex(using context: ModelContext) {
        backfillNoteSearchIndex(using: cdViewContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func backfillWorkCompletionRecords(using context: ModelContext) {
        MainActor.assumeIsolated {
            RelationshipBackfillService.backfillWorkCompletionRecords(using: cdViewContext)
        }
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func migrateWorkTypeToKind(using context: ModelContext) {
        MainActor.assumeIsolated {
            RelationshipBackfillService.migrateWorkTypeToKind(using: cdViewContext)
        }
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    static func migrateNoteCategoryToTagsIfNeeded(using context: ModelContext) async {
        await SchemaMigrationService.migrateNoteCategoryToTagsIfNeeded(using: cdViewContext)
    }

    /// Note category to tags migration — Core Data version.
    static func migrateNoteCategoryToTagsIfNeeded(using context: NSManagedObjectContext) async {
        await SchemaMigrationService.migrateNoteCategoryToTagsIfNeeded(using: context)
    }
}
