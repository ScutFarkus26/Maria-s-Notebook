import Foundation
import SwiftData
import OSLog

// MARK: - Data Cleanup Service

/// Service responsible for cleaning up orphaned data and maintaining referential integrity.
/// Handles cleanup of orphaned student IDs, duplicate records, and other data integrity issues.
enum DataCleanupService {
    static let logger = Logger.migration

    // MARK: - Run All Cleanup Operations

    /// Runs all data cleanup operations in sequence.
    /// Safe to call repeatedly - each operation is idempotent.
    static func runAllCleanupOperations(using context: ModelContext) async {
        // Run comprehensive deduplication first since other cleanups depend on valid data
        _ = deduplicateAllModels(using: context)
        await cleanOrphanedStudentIDs(using: context)
        await cleanOrphanedWorkStudentIDs(using: context)
        deduplicateDraftLessonAssignments(using: context)
        await repairScopeForContextualNotes(using: context)
        await repairDenormalizedScheduledForDay(using: context)
    }
}
