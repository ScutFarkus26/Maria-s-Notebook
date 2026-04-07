import CoreData
import Foundation
import OSLog

enum MigrationRunner {
    private static let logger = Logger.migration

    @MainActor static func runIfNeeded(context: NSManagedObjectContext) async {
        // Remove duplicate records that may have been created by CloudKit sync conflicts.
        let deduplicationResults = DataMigrations.deduplicateAllModels(using: context)
        for (modelType, count) in deduplicationResults.sorted(by: { $0.key < $1.key }) {
            logger.info("Removed \(count, privacy: .public) duplicate \(modelType, privacy: .public) record(s)")
        }

        // Clean orphaned student IDs from CDWorkModel records
        await DataMigrations.cleanOrphanedWorkStudentIDs(using: context)

        // Clean up any orphaned note images
        DataMigrations.cleanupOrphanedNoteImages(using: context)

        // Create NoteStudentLink records for efficient multi-student scope queries
        DataMigrations.createNoteStudentLinksForExistingNotes(using: context)

        // Backfill search index so scope getter no longer self-heals
        DataMigrations.backfillNoteSearchIndex(using: context)

        // Backfill student/track relationships for CloudKit zone assignment
        DataMigrations.backfillTrackEnrollmentRelationships(using: context)
    }
}
