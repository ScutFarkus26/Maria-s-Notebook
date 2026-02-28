import Foundation
import SwiftData
import OSLog

// MARK: - Schema Migration Service

/// Service responsible for schema-level migrations and format conversions.
/// Handles migrations for data format changes like UUID to String conversions,
/// property storage format changes, and other schema-related updates.
enum SchemaMigrationService {
    private static let logger = Logger.migration

    // MARK: - Date Normalization

    /// StudentLesson model removed — migration complete. Marks flag if not already set.
    static func normalizeGivenAtToDateOnlyIfNeeded(using context: ModelContext) async {
        let flagKey = "Migration.givenAtDateOnly.v1"
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
        }
    }

    // MARK: - UUID to String Migrations

    /// Migrate AttendanceRecord.studentID from UUID to String format.
    /// This must be called after the store is opened, as it uses ModelContext.
    /// Idempotent: guarded by a UserDefaults flag.
    static func migrateAttendanceRecordStudentIDToStringIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.attendanceRecordStudentIDToString.v1"
        _ = MigrationFlag.runIfNeeded(key: flagKey) {
            let fetch = FetchDescriptor<AttendanceRecord>()
            let records = context.safeFetch(fetch)

            for record in records {
                let currentValue = record.studentID

                if currentValue.isEmpty {
                    continue
                }

                // If it's already a valid UUID string format, it's already migrated
                if UUID(uuidString: currentValue) != nil {
                    continue
                }
            }
        }
    }

    // MARK: - GroupTrack Migration

    /// Migrate GroupTrack records to include isExplicitlyDisabled field.
    /// Sets all existing GroupTrack records to isExplicitlyDisabled = false (they remain as tracks).
    /// New default behavior: All groups are tracks (sequential) unless explicitly disabled.
    /// Idempotent: guarded by a UserDefaults flag.
    static func migrateGroupTracksToDefaultBehaviorIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.groupTracksDefaultBehavior.v1"
        _ = MigrationFlag.runIfNeeded(key: flagKey) {
            let tracks = context.safeFetch(FetchDescriptor<GroupTrack>())
            var updated = 0

            for track in tracks {
                if track.isExplicitlyDisabled {
                    track.isExplicitlyDisabled = false
                    updated += 1
                }
            }

            if updated > 0 {
                context.safeSave()
            }
        }
    }

    // MARK: - Legacy StudentLesson Sync (no-op)

    /// StudentLesson model removed — migration complete. Marks flag if not already set.
    static func syncStudentLessonIDsFromRelationshipsIfNeeded(using context: ModelContext) async {
        let flagKey = "Migration.studentLessonIDSync.v1"
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
        }
    }

    // MARK: - WorkModel Migration

    /// StudentLesson model removed — WorkModel ID backfill from StudentLesson is no longer possible.
    /// Any WorkModels that needed backfill should have been handled before the model was removed.
    static func migrateWorkContractsToWorkModelsIfNeeded(using context: ModelContext) async {
        // No-op: StudentLesson model removed. Migration complete.
    }

    // MARK: - Note Category to Tags Migration

    /// Migrates Note and NoteTemplate records from the legacy categoryRaw field to the new tags array.
    /// Converts each category to a tag in "Name|Color" format using TagHelper.
    /// Idempotent: guarded by a UserDefaults flag, only updates records where tags is empty.
    static func migrateNoteCategoryToTagsIfNeeded(using context: ModelContext) async {
        let flagKey = "Migration.noteCategoryToTags.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            // Migrate Notes
            let notes = context.safeFetch(FetchDescriptor<Note>())
            var notesChanged = 0
            for (index, note) in notes.enumerated() {
                if index % 100 == 0 { await Task.yield() }
                if note.tags.isEmpty {
                    let categoryRaw = note.legacyCategoryRaw
                    if !categoryRaw.isEmpty && categoryRaw != "general" {
                        note.tags = [TagHelper.tagFromNoteCategory(categoryRaw)]
                        notesChanged += 1
                    }
                }
            }

            // Migrate NoteTemplates
            let templates = context.safeFetch(FetchDescriptor<NoteTemplate>())
            var templatesChanged = 0
            for template in templates {
                if template.tags.isEmpty {
                    let categoryRaw = template.legacyCategoryRaw
                    if !categoryRaw.isEmpty && categoryRaw != "general" {
                        template.tags = [TagHelper.tagFromNoteCategory(categoryRaw)]
                        templatesChanged += 1
                    }
                }
            }

            if notesChanged > 0 || templatesChanged > 0 {
                context.safeSave()
                logger.info("Migrated \(notesChanged) notes and \(templatesChanged) templates from category to tags")
            }
        }
    }

    // MARK: - Run All Schema Migrations

    /// Runs all schema migrations in sequence.
    /// Safe to call repeatedly - each migration is idempotent.
    static func runAllSchemaMigrations(using context: ModelContext) async {
        await normalizeGivenAtToDateOnlyIfNeeded(using: context)
        migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)
        migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)
        await syncStudentLessonIDsFromRelationshipsIfNeeded(using: context)
        await migrateWorkContractsToWorkModelsIfNeeded(using: context)
        await migrateNoteCategoryToTagsIfNeeded(using: context)
    }
}
