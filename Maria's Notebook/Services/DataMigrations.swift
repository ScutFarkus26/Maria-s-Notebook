import Foundation
import SwiftData
import CoreData

// MARK: - Data Migrations Facade

/// Central facade for all data migrations.
/// Delegates to specialized migration services for better organization and maintainability.
///
/// Migration services:
/// - `SchemaMigrationService`: Schema-level migrations (UUID to String, format changes)
/// - `RelationshipBackfillService`: Relationship backfilling between entities
/// - `LegacyNotesMigrationService`: Legacy string notes to Note objects
/// - `DataCleanupService`: Orphaned data cleanup and deduplication
enum DataMigrations {

    // MARK: - Schema Migrations (delegated to SchemaMigrationService)

    /// Normalize all existing StudentLesson.givenAt values to start-of-day (strip time) once.
    static func normalizeGivenAtToDateOnlyIfNeeded(using context: ModelContext) async {
        await SchemaMigrationService.normalizeGivenAtToDateOnlyIfNeeded(using: context)
    }

    /// Fix CommunityTopic.tags property migration to new storage format.
    static func fixCommunityTopicTagsIfNeeded(using context: ModelContext) {
        SchemaMigrationService.fixCommunityTopicTagsIfNeeded(using: context)
    }

    /// Fix StudentLesson.studentIDs property migration to new storage format.
    static func fixStudentLessonStudentIDsIfNeeded(using context: ModelContext) {
        SchemaMigrationService.fixStudentLessonStudentIDsIfNeeded(using: context)
    }

    /// Migrate UUID foreign keys to String format for CloudKit compatibility.
    static func migrateUUIDForeignKeysToStringsIfNeeded(using context: ModelContext) {
        SchemaMigrationService.migrateUUIDForeignKeysToStringsIfNeeded(using: context)
    }

    /// Migrate AttendanceRecord.studentID from UUID to String format.
    static func migrateAttendanceRecordStudentIDToStringIfNeeded(using context: ModelContext) {
        SchemaMigrationService.migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)
    }

    /// Migrate GroupTrack records to include isExplicitlyDisabled field.
    static func migrateGroupTracksToDefaultBehaviorIfNeeded(using context: ModelContext) {
        SchemaMigrationService.migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)
    }

    /// Backfill WorkModel IDs from StudentLesson where needed.
    @MainActor
    static func migrateWorkContractsToWorkModelsIfNeeded(using context: ModelContext) async {
        await SchemaMigrationService.migrateWorkContractsToWorkModelsIfNeeded(using: context)
    }

    // MARK: - Data Cleanup (delegated to DataCleanupService)

    /// Remove duplicate Student records that have the same UUID.
    /// This can happen when CloudKit sync creates duplicates during merge conflicts.
    @discardableResult
    static func deduplicateStudents(using context: ModelContext) -> Int {
        DataCleanupService.deduplicateStudents(using: context)
    }

    /// Remove duplicate Project records that have the same UUID.
    /// This can happen when CloudKit sync creates duplicates during merge conflicts.
    @discardableResult
    static func deduplicateProjects(using context: ModelContext) -> Int {
        DataCleanupService.deduplicateProjects(using: context)
    }

    /// Remove duplicate ProjectRole records that have the same UUID.
    /// This can happen when CloudKit sync creates duplicates during merge conflicts.
    @discardableResult
    static func deduplicateProjectRoles(using context: ModelContext) -> Int {
        DataCleanupService.deduplicateProjectRoles(using: context)
    }

    /// Deduplicate unscheduled, unpresented StudentLesson records.
    static func deduplicateUnpresentedStudentLessons(using context: ModelContext) {
        DataCleanupService.deduplicateUnpresentedStudentLessons(using: context)
    }

    /// Repairs denormalized scheduledForDay fields to match scheduledFor.
    static func repairDenormalizedScheduledForDay(using context: ModelContext) async {
        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)
    }

    /// Cleans orphaned student IDs from StudentLesson records.
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
    @MainActor
    static func cleanupOrphanedNoteImages(using context: ModelContext) {
        DataCleanupService.cleanupOrphanedNoteImages(using: context)
    }

    /// Create NoteStudentLink records for existing notes with multi-student scope.
    @MainActor
    static func createNoteStudentLinksForExistingNotes(using context: ModelContext) {
        DataCleanupService.createNoteStudentLinksForExistingNotes(using: context)
    }

    // MARK: - Relationship Backfills (delegated to RelationshipBackfillService)

    /// Backfill StudentLesson relationships from legacy studentIDs and lessonID strings.
    static func backfillRelationshipsIfNeeded(using context: ModelContext) async {
        await RelationshipBackfillService.backfillRelationshipsIfNeeded(using: context)
    }

    /// Backfill isPresented flag from givenAt field.
    static func backfillIsPresentedIfNeeded(using context: ModelContext) async {
        await RelationshipBackfillService.backfillIsPresentedIfNeeded(using: context)
    }

    /// Backfill scheduledForDay field from scheduledFor.
    static func backfillScheduledForDayIfNeeded(using context: ModelContext) async {
        await RelationshipBackfillService.backfillScheduledForDayIfNeeded(using: context)
    }

    /// Backfill Presentation.legacyStudentLessonID by linking to matching StudentLessons.
    static func backfillPresentationStudentLessonLinks(using context: ModelContext) async {
        await RelationshipBackfillService.backfillPresentationStudentLessonLinks(using: context)
    }

    /// Repairs Presentation.legacyStudentLessonID for existing records.
    static func repairPresentationStudentLessonLinks_v2(using context: ModelContext) async {
        await RelationshipBackfillService.repairPresentationStudentLessonLinks_v2(using: context)
    }

    /// Backfill Note.studentLesson for notes attached to Presentations.
    static func backfillNoteStudentLessonFromPresentation(using context: ModelContext) async {
        await RelationshipBackfillService.backfillNoteStudentLessonFromPresentation(using: context)
    }

    // MARK: - Legacy Notes Migrations (delegated to LegacyNotesMigrationService)

    /// Migrate legacy string notes on WorkModels into Note objects.
    @MainActor
    static func migrateLegacyWorkNotesToNoteObjects(using context: ModelContext) {
        LegacyNotesMigrationService.migrateWorkNotes(using: context)
    }

    /// Migrate legacy string notes on StudentLesson into Note objects.
    @MainActor
    static func migrateLegacyStudentLessonNotes(using context: ModelContext) {
        LegacyNotesMigrationService.migrateStudentLessonNotes(using: context)
    }

    /// Migrate legacy string notes on WorkCheckIn into Note objects.
    @MainActor
    static func migrateLegacyWorkCheckInNotes(using context: ModelContext) {
        LegacyNotesMigrationService.migrateWorkCheckInNotes(using: context)
    }

    /// Migrate legacy string notes on WorkCompletionRecord into Note objects.
    @MainActor
    static func migrateLegacyWorkCompletionRecordNotes(using context: ModelContext) {
        LegacyNotesMigrationService.migrateWorkCompletionRecordNotes(using: context)
    }

    /// Migrate legacy string notes on AttendanceRecord into Note objects.
    @MainActor
    static func migrateLegacyAttendanceNotes(using context: ModelContext) {
        LegacyNotesMigrationService.migrateAttendanceNotes(using: context)
    }

    /// Migrate legacy string notes on ProjectSession into Note objects.
    @MainActor
    static func migrateLegacyProjectSessionNotes(using context: ModelContext) {
        LegacyNotesMigrationService.migrateProjectSessionNotes(using: context)
    }

    /// Migrate legacy string notes on StudentTrackEnrollment into Note objects.
    @MainActor
    static func migrateLegacyStudentTrackEnrollmentNotes(using context: ModelContext) {
        LegacyNotesMigrationService.migrateStudentTrackEnrollmentNotes(using: context)
    }

    /// Migrate legacy string notes on WorkPlanItem into Note objects.
    @MainActor
    static func migrateLegacyWorkPlanItemNotes(using context: ModelContext) {
        LegacyNotesMigrationService.migrateWorkPlanItemNotes(using: context)
    }

    /// Migrate legacy string notes on SchoolDayOverride into Note objects.
    @MainActor
    static func migrateLegacySchoolDayOverrideNotes(using context: ModelContext) {
        LegacyNotesMigrationService.migrateSchoolDayOverrideNotes(using: context)
    }

    /// Migrate legacy string notes on Reminder into Note objects.
    @MainActor
    static func migrateLegacyReminderNotes(using context: ModelContext) {
        LegacyNotesMigrationService.migrateReminderNotes(using: context)
    }
}
