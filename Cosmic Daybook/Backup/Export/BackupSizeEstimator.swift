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

    /// Estimates the backup size in bytes based on current entity counts.
    ///
    /// - Parameter viewContext: The model context to count entities from
    /// - Returns: Estimated compressed backup size in bytes
    static func estimateBackupSize(viewContext: NSManagedObjectContext) -> Int64 {
        let counts = countEntities(viewContext: viewContext)
        return estimateFromCounts(counts)
    }

    /// Counts all exportable entities in the database.
    ///
    /// - Parameter viewContext: The model context to count entities from
    /// - Returns: Dictionary mapping entity type names to counts
    static func countEntities(viewContext: NSManagedObjectContext) -> [String: Int] {
        var counts: [String: Int] = [:]

        counts["Student"] = safeFetchCount(CDStudent.self, using: viewContext)
        counts["Lesson"] = safeFetchCount(CDLesson.self, using: viewContext)
        counts["Note"] = safeFetchCount(CDNote.self, using: viewContext)
        counts["NonSchoolDay"] = safeFetchCount(CDNonSchoolDay.self, using: viewContext)
        counts["SchoolDayOverride"] = safeFetchCount(CDSchoolDayOverride.self, using: viewContext)
        counts["StudentMeeting"] = safeFetchCount(CDStudentMeeting.self, using: viewContext)
        counts["CommunityTopic"] = safeFetchCount(CDCommunityTopicEntity.self, using: viewContext)
        counts["ProposedSolution"] = safeFetchCount(CDProposedSolutionEntity.self, using: viewContext)
        counts["CommunityAttachment"] = safeFetchCount(CDCommunityAttachment.self, using: viewContext)
        counts["AttendanceRecord"] = safeFetchCount(CDAttendanceRecord.self, using: viewContext)
        counts["WorkCompletionRecord"] = safeFetchCount(CDWorkCompletionRecord.self, using: viewContext)
        counts["Project"] = safeFetchCount(CDProject.self, using: viewContext)
        counts["ProjectAssignmentTemplate"] = 0 // Deprecated
        counts["ProjectSession"] = safeFetchCount(CDProjectSession.self, using: viewContext)
        counts["ProjectRole"] = safeFetchCount(CDProjectRole.self, using: viewContext)
        counts["ProjectTemplateWeek"] = 0 // Deprecated
        counts["ProjectWeekRoleAssignment"] = 0 // Deprecated

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

    private static func safeFetchCount<T: NSManagedObject>(
        _ type: T.Type, using context: NSManagedObjectContext
    ) -> Int {
        // The name comes from this context's model, and a type it doesn't hold is
        // skipped: `T.entity()` is ambiguous once a process has loaded more than one
        // model, and a wrong entity name throws an ObjC NSException that Swift
        // catch cannot intercept.
        guard let entityName = BackupFetchHelper.entityName(for: T.self, in: context) else {
            return 0
        }
        let descriptor = NSFetchRequest<T>(entityName: entityName)
        do {
            return try context.count(for: descriptor)
        } catch {
            logger.warning("Failed to fetch count for \(T.self): \(error)")
            return 0
        }
    }
}
