import CoreData
import SwiftData
import Foundation
import OSLog

enum MigrationRunner {
    private static let logger = Logger.migration

    // MARK: - Core Data API (Primary)

    @MainActor static func runIfNeeded(context: NSManagedObjectContext) async {
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

        // TODO: Remove after a few releases — backfills search index so scope getter no longer self-heals
        DataMigrations.backfillNoteSearchIndex(using: context)

        // Backfill WorkCompletionRecord from WorkParticipantEntity.completedAt
        // This preserves all historical completion data in the new system
        DataMigrations.backfillWorkCompletionRecords(using: context)

        // Migrate WorkType to WorkKind (consolidate dual enum systems)
        DataMigrations.migrateWorkTypeToKind(using: context)

        // PHASE 6 COMPLETE: Legacy check-in migration finished and model removed
        // Backfill and cleanup migrations no longer needed as legacy model is deleted

        // TODO: Convert NoteTemplate/MeetingTemplate seeding to Core Data in a future batch
        // These still use SwiftData models and are called via the deprecated bridge below
    }

    /// Seed templates that still require a ModelContext (SwiftData).
    /// Call this alongside `runIfNeeded(context:)` until the template models are converted.
    static func seedTemplatesIfNeeded(modelContext: ModelContext) {
        NoteTemplate.seedBuiltInTemplates(in: modelContext)
        MeetingTemplate.seedBuiltInTemplates(in: modelContext)
    }

    // MARK: - Deprecated SwiftData Bridge

    @available(*, deprecated, message: "Use runIfNeeded(context:) with NSManagedObjectContext")
    @MainActor static func runIfNeeded(context: ModelContext) async {
        let cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        await runIfNeeded(context: cdContext)


        // Seed templates via SwiftData (still needs ModelContext)
        seedTemplatesIfNeeded(modelContext: context)
    }
}
