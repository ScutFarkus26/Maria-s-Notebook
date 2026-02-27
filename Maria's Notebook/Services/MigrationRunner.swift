import SwiftData
import Foundation
import OSLog

enum MigrationRunner {
    private static let logger = Logger.migration

    static func runIfNeeded(context: ModelContext) async {
        // Remove duplicate records that may have been created by CloudKit sync conflicts.
        // This must run early before other migrations that depend on clean data.
        let deduplicationResults = DataMigrations.deduplicateAllModels(using: context)
        for (modelType, count) in deduplicationResults.sorted(by: { $0.key < $1.key }) {
            logger.info("Removed \(count, privacy: .public) duplicate \(modelType, privacy: .public) record(s)")
        }

        // Clean orphaned student IDs from WorkModel records
        await DataMigrations.cleanOrphanedWorkStudentIDs(using: context)

        // Clean up any orphaned note images
        DataMigrations.cleanupOrphanedNoteImages(using: context)

        // Create NoteStudentLink records for efficient multi-student scope queries
        DataMigrations.createNoteStudentLinksForExistingNotes(using: context)

        // Backfill WorkCompletionRecord from WorkParticipantEntity.completedAt
        // This preserves all historical completion data in the new system
        DataMigrations.backfillWorkCompletionRecords(using: context)

        // Migrate WorkType to WorkKind (consolidate dual enum systems)
        DataMigrations.migrateWorkTypeToKind(using: context)

        // PHASE 6 COMPLETE: Legacy check-in migration finished and model removed
        // Backfill and cleanup migrations no longer needed as legacy model is deleted

        // Seed built-in note templates
        NoteTemplate.seedBuiltInTemplates(in: context)

        // Seed built-in meeting templates
        MeetingTemplate.seedBuiltInTemplates(in: context)
    }
}
