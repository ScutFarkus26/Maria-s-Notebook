import Foundation
import CoreData
import OSLog

/// Estimates backup file sizes based on entity counts.
///
/// This provides size estimation functionality extracted from BackupService
/// for better testability and reuse.
enum BackupSizeEstimator {
    private static let logger = Logger.backup
    /// Average bytes per entity type (empirically determined)
    static let averageBytesPerEntity: [String: Int] = [
        "Student": 600,
        "Lesson": 2500,
        "Note": 300,
        "NonSchoolDay": 200,
        "SchoolDayOverride": 200,
        "StudentMeeting": 1200,
        "CommunityTopic": 1500,
        "ProposedSolution": BatchingConstants.estimatedBytesPerEntity,
        "CommunityAttachment": 600,
        "AttendanceRecord": 300,
        "WorkCompletionRecord": 400,
        "Project": 2000,
        "ProjectAssignmentTemplate": 2500,
        "ProjectSession": 1500,
        "ProjectRole": 1200,
        "ProjectTemplateWeek": 1800,
        "ProjectWeekRoleAssignment": 300
    ]

    /// Default bytes per entity when type is unknown
    static let defaultBytesPerEntity: Int = BatchingConstants.estimatedBytesPerEntity

    /// Overhead for the backup envelope (metadata, headers, etc.)
    static let envelopeOverhead: Int64 = 2048

    /// Expected compression ratio for LZFSE compression
    static let compressionRatio: Double = 3.0

    /// Estimates the backup size in bytes based on current entity counts,
    /// plus the note photos on this device when backups include them (photo
    /// files are already compressed, so counted at their own size).
    ///
    /// - Parameter viewContext: The model context to count entities from
    /// - Returns: Estimated compressed backup size in bytes
    static func estimateBackupSize(
        viewContext: NSManagedObjectContext, includesPhotos: Bool = BackupPhotos.includesNotePhotos
    ) -> Int64 {
        let counts = countEntities(viewContext: viewContext)
        let photoBytes = includesPhotos
            ? BackupPhotos.localBytes(for: BackupPhotos.referencedFilenames(in: viewContext)) : 0
        return estimateFromCounts(counts) + photoBytes
    }

    /// Counts every backed-up entity type (`BackupEntityTable`) in the
    /// notebook. Until 2026-11 a hand-kept list counted 15 of the 82 types,
    /// so the card's estimate left out most of the notebook (bug hunt
    /// 2026-11-02 #21).
    ///
    /// - Parameter viewContext: The model context to count entities from
    /// - Returns: Dictionary mapping entity type names to counts
    static func countEntities(viewContext: NSManagedObjectContext) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entity in BackupEntityTable.entities {
            counts[entity.name] = safeFetchCount(entity.managedType(), using: viewContext)
        }
        return counts
    }

    /// Estimates backup size from entity counts dictionary.
    ///
    /// - Parameter counts: Dictionary mapping entity type names to counts
    /// - Returns: Estimated compressed backup size in bytes
    static func estimateFromCounts(_ counts: [String: Int]) -> Int64 {
        let uncompressedSize = counts.reduce(0) { (total: Int, pair: (key: String, value: Int)) -> Int in
            let averageSize = averageBytesPerEntity[pair.key] ?? defaultBytesPerEntity
            return total + (averageSize * pair.value)
        }

        let compressedSize = Int64(Double(uncompressedSize) / compressionRatio)

        return compressedSize + envelopeOverhead
    }

    // MARK: - Private Helpers

    /// The rows of `type` a backup would hold: the notebook's own, as the
    /// export reads them (`BackupRestoreScope.limitToNotebook`).
    private static func safeFetchCount(
        _ type: NSManagedObject.Type, using context: NSManagedObjectContext
    ) -> Int {
        // The name comes from this context's model, and a type it doesn't hold is
        // skipped: `T.entity()` is ambiguous once a process has loaded more than one
        // model, and a wrong entity name throws an ObjC NSException that Swift
        // catch cannot intercept.
        guard let entityName = BackupFetchHelper.entityName(for: type, in: context) else {
            return 0
        }
        let descriptor = NSFetchRequest<NSManagedObject>(entityName: entityName)
        BackupRestoreScope.limitToNotebook(descriptor, in: context)
        do {
            return try context.count(for: descriptor)
        } catch {
            logger.warning("Failed to fetch count for \(entityName, privacy: .public): \(error)")
            return 0
        }
    }
}
