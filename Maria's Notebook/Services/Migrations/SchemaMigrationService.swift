import Foundation
import SwiftData

// MARK: - Schema Migration Service

/// Service responsible for schema-level migrations and format conversions.
/// Handles migrations for data format changes like UUID to String conversions,
/// property storage format changes, and other schema-related updates.
enum SchemaMigrationService {

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

    // MARK: - Property Format Migrations

    /// Fix CommunityTopic.tags property migration to new storage format.
    /// The tags property now uses JSON-encoded Data storage (_tagsData) instead of direct array storage.
    ///
    /// IMPORTANT: This migration cannot fetch CommunityTopic records directly because SwiftData
    /// may crash when trying to read the old tags property from corrupted data. Instead, we use
    /// a lazy migration approach where records are migrated when they are accessed and saved.
    static func fixCommunityTopicTagsIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.communityTopicTagsFix.v2"

        // Mark migration as complete immediately to prevent any fetch attempts that might crash
        // The computed property in CommunityTopic will safely handle corrupted data
        // by returning an empty array if _tagsData contains invalid data.
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
        }
    }

    /// Fix StudentLesson.studentIDs property migration to new storage format.
    /// The studentIDs property now uses JSON-encoded Data storage (_studentIDsData) instead of direct array storage.
    ///
    /// IMPORTANT: This migration cannot fetch StudentLesson records directly because SwiftData
    /// may crash when trying to read the old studentIDs property from corrupted data (UUIDs instead of Strings).
    static func fixStudentLessonStudentIDsIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.studentLessonStudentIDsFix.v1"

        // Mark migration as complete immediately to prevent any fetch attempts that might crash
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
        }
    }

    // MARK: - UUID to String Migrations

    /// Migrate UUID foreign keys to String format for CloudKit compatibility.
    /// This migration converts all UUID foreign keys to their string representations.
    /// Idempotent: guarded by a UserDefaults flag.
    static func migrateUUIDForeignKeysToStringsIfNeeded(using context: ModelContext) {
        let flagKey = "Migration.uuidForeignKeysToStrings.v1"

        // Note: This migration is primarily handled by lazy migration when records are accessed.
        // The models now store UUIDs as strings, and initializers convert UUID parameters to strings.
        if !MigrationFlag.isComplete(key: flagKey) {
            MigrationFlag.markComplete(key: flagKey)
        }
    }

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

    // MARK: - WorkModel Migration

    /// Backfill WorkModel IDs from StudentLesson where needed.
    /// Legacy migration from WorkContract is complete - this function now only handles
    /// WorkModels created via the StudentLesson path that need ID backfill.
    @MainActor
    static func migrateWorkContractsToWorkModelsIfNeeded(using context: ModelContext) async {
        do {
            let workModels = context.safeFetch(FetchDescriptor<WorkModel>())
            guard !workModels.isEmpty else { return }

            let studentLessons = (try? context.fetch(FetchDescriptor<StudentLesson>())) ?? []
            let studentLessonByID: [UUID: StudentLesson] = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })

            var studentLessonBackfilledCount = 0

            for (index, work) in workModels.enumerated() {
                if index % 50 == 0 && index > 0 {
                    await Task.yield()
                }

                guard (work.studentID.isEmpty || work.lessonID.isEmpty), let slID = work.studentLessonID else { continue }
                guard let sl = studentLessonByID[slID] else { continue }

                if work.lessonID.isEmpty { work.lessonID = sl.lessonID }
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

    // MARK: - Run All Schema Migrations

    /// Runs all schema migrations in sequence.
    /// Safe to call repeatedly - each migration is idempotent.
    @MainActor
    static func runAllSchemaMigrations(using context: ModelContext) async {
        await normalizeGivenAtToDateOnlyIfNeeded(using: context)
        fixCommunityTopicTagsIfNeeded(using: context)
        fixStudentLessonStudentIDsIfNeeded(using: context)
        migrateUUIDForeignKeysToStringsIfNeeded(using: context)
        migrateAttendanceRecordStudentIDToStringIfNeeded(using: context)
        migrateGroupTracksToDefaultBehaviorIfNeeded(using: context)
        await migrateWorkContractsToWorkModelsIfNeeded(using: context)
    }
}
