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

    /// Normalize all existing StudentLesson.givenAt values to start-of-day (strip time) once.
    /// Idempotent: guarded by a UserDefaults flag and only updates rows where time != start of day.
    static func normalizeGivenAtToDateOnlyIfNeeded(using context: ModelContext) async {
        let flagKey = "Migration.givenAtDateOnly.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            let calendar = AppCalendar.shared
            let fetch = FetchDescriptor<StudentLesson>()
            let lessons = context.safeFetch(fetch)
            var changed = 0
            for (index, sl) in lessons.enumerated() {
                if index % 100 == 0 { await Task.yield() }
                if let dt = sl.givenAt {
                    let normalized = calendar.startOfDay(for: dt)
                    if dt != normalized {
                        sl.givenAt = normalized
                        changed += 1
                    }
                }
            }
            if changed > 0 { context.safeSave() }
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

    // MARK: - StudentLesson LessonID Sync
    
    /// Sync StudentLesson.lessonID from lesson relationship where missing.
    /// Fixes records where the lessonID string field is empty but the relationship exists.
    /// Idempotent: only updates records where lessonID is empty and lesson relationship exists.
    static func syncStudentLessonIDsFromRelationshipsIfNeeded(using context: ModelContext) async {
        let flagKey = "Migration.studentLessonIDSync.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            let fetch = FetchDescriptor<StudentLesson>()
            let lessons = context.safeFetch(fetch)
            var synced = 0
            
            for (index, sl) in lessons.enumerated() {
                if index % 100 == 0 { await Task.yield() }
                
                // Only sync if lessonID is empty and lesson relationship exists
                if sl.lessonID.isEmpty, let lesson = sl.lesson {
                    sl.lessonID = lesson.id.uuidString
                    synced += 1
                }
            }
            
            if synced > 0 {
                context.safeSave()
            }
        }
    }

    // MARK: - WorkModel Migration

    /// Backfill WorkModel IDs from StudentLesson where needed.
    /// Legacy migration from WorkContract is complete - this function now only handles
    /// WorkModels created via the StudentLesson path that need ID backfill.
    static func migrateWorkContractsToWorkModelsIfNeeded(using context: ModelContext) async {
        do {
            let workModels = context.safeFetch(FetchDescriptor<WorkModel>())
            guard !workModels.isEmpty else { return }

            // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
            let studentLessons: [StudentLesson]
            do {
                studentLessons = try context.fetch(FetchDescriptor<StudentLesson>()).uniqueByID
            } catch {
                logger.warning("Failed to fetch StudentLessons: \(error.localizedDescription)")
                return
            }
            let studentLessonByID: [UUID: StudentLesson] = Dictionary(studentLessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            var studentLessonBackfilledCount = 0

            for (index, work) in workModels.enumerated() {
                if index % 50 == 0 && index > 0 {
                    await Task.yield()
                }

                guard (work.studentID.isEmpty || work.lessonID.isEmpty), let slID = work.studentLessonID else { continue }
                guard let sl = studentLessonByID[slID] else { continue }

                if work.lessonID.isEmpty {
                    // Priority: Use lesson relationship if available, otherwise use lessonID string
                    if let lesson = sl.lesson {
                        work.lessonID = lesson.id.uuidString
                    } else if !sl.lessonID.isEmpty {
                        work.lessonID = sl.lessonID
                    }
                }
                if work.studentID.isEmpty {
                    if let firstStudent = sl.studentIDs.first {
                        work.studentID = firstStudent
                    }
                }
                if work.legacyStudentLessonID == nil { work.legacyStudentLessonID = slID.uuidString }
                studentLessonBackfilledCount += 1
            }

            if studentLessonBackfilledCount > 0 {
                try context.save()
            }
        } catch {
            // WorkModel ID backfill failed - continue silently
        }
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
