import SwiftData
import Foundation

enum MigrationRunner {
    static func runIfNeeded(context: ModelContext) async {
        let key = "MigrationRunner.v1.practiceFollowUpBackfill"
        // Disabled: Do not fetch or mutate WorkModel at startup.
        // Mark as done to avoid reruns while retaining compatibility flags.
        MigrationFlag.markComplete(key: key)

        // Remove duplicate records that may have been created by CloudKit sync conflicts.
        // This must run early before other migrations that depend on clean data.
        let removedStudents = DataMigrations.deduplicateStudents(using: context)
        if removedStudents > 0 {
            print("[MigrationRunner] Removed \(removedStudents) duplicate student record(s)")
        }
        let removedProjects = DataMigrations.deduplicateProjects(using: context)
        if removedProjects > 0 {
            print("[MigrationRunner] Removed \(removedProjects) duplicate project record(s)")
        }
        let removedRoles = DataMigrations.deduplicateProjectRoles(using: context)
        if removedRoles > 0 {
            print("[MigrationRunner] Removed \(removedRoles) duplicate project role record(s)")
        }

        // Migrate legacy string notes on WorkModels to Note objects
        Task { @MainActor in
            DataMigrations.migrateLegacyWorkNotesToNoteObjects(using: context)
        }

        // Clean orphaned student IDs from WorkModel records
        await DataMigrations.cleanOrphanedWorkStudentIDs(using: context)

        // Migrate all legacy string notes to unified Note objects
        Task { @MainActor in
            DataMigrations.migrateLegacyStudentLessonNotes(using: context)
            DataMigrations.migrateLegacyWorkCheckInNotes(using: context)
            DataMigrations.migrateLegacyWorkCompletionRecordNotes(using: context)
            DataMigrations.migrateLegacyAttendanceNotes(using: context)
            DataMigrations.migrateLegacyProjectSessionNotes(using: context)
            DataMigrations.migrateLegacyStudentTrackEnrollmentNotes(using: context)
            DataMigrations.migrateLegacyWorkPlanItemNotes(using: context)
            DataMigrations.migrateLegacySchoolDayOverrideNotes(using: context)
            DataMigrations.migrateLegacyReminderNotes(using: context)

            // Clean up any orphaned note images after migrations
            DataMigrations.cleanupOrphanedNoteImages(using: context)

            // Create NoteStudentLink records for efficient multi-student scope queries
            DataMigrations.createNoteStudentLinksForExistingNotes(using: context)

            // Seed built-in note templates
            NoteTemplate.seedBuiltInTemplates(in: context)
        }
    }
}
