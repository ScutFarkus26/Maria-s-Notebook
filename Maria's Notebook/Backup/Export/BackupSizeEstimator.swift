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
        "CDStudent": 600,
        "CDLesson": 2500,
        "LegacyPresentation": 300,
        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        "CDNote": 300,
        "CDNonSchoolDay": 200,
        "CDSchoolDayOverride": 200,
        "CDStudentMeeting": 1200,
        // CDPresentation removed - using CDLessonAssignment instead
        "CDCommunityTopicEntity": 1500,
        "ProposedSolution": BatchingConstants.estimatedBytesPerEntity,
        "CommunityAttachment": 600,
        "CDAttendanceRecord": 300,
        "CDWorkCompletionRecord": 400,
        "CDProject": 2000,
        "ProjectAssignmentTemplate": 2500,
        "CDProjectSession": 1500,
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

        counts["CDStudent"] = safeFetchCount(CDStudent.self, using: viewContext)
        counts["CDLesson"] = safeFetchCount(CDLesson.self, using: viewContext)
        // LegacyPresentation removed — fully migrated to CDLessonAssignment
        // WorkPlanItem removed in Phase 6 - migrated to CDWorkCheckIn
        counts["CDNote"] = safeFetchCount(CDNote.self, using: viewContext)
        counts["CDNonSchoolDay"] = safeFetchCount(CDNonSchoolDay.self, using: viewContext)
        counts["CDSchoolDayOverride"] = safeFetchCount(CDSchoolDayOverride.self, using: viewContext)
        counts["CDStudentMeeting"] = safeFetchCount(CDStudentMeeting.self, using: viewContext)
        // CDPresentation removed - using CDLessonAssignment instead
        counts["CDCommunityTopicEntity"] = safeFetchCount(CDCommunityTopicEntity.self, using: viewContext)
        counts["ProposedSolution"] = safeFetchCount(ProposedSolution.self, using: viewContext)
        counts["CommunityAttachment"] = safeFetchCount(CommunityAttachment.self, using: viewContext)
        counts["CDAttendanceRecord"] = safeFetchCount(CDAttendanceRecord.self, using: viewContext)
        counts["CDWorkCompletionRecord"] = safeFetchCount(CDWorkCompletionRecord.self, using: viewContext)
        counts["CDProject"] = safeFetchCount(CDProject.self, using: viewContext)
        counts["ProjectAssignmentTemplate"] = safeFetchCount(ProjectAssignmentTemplate.self, using: viewContext)
        counts["CDProjectSession"] = safeFetchCount(CDProjectSession.self, using: viewContext)
        counts["ProjectRole"] = safeFetchCount(ProjectRole.self, using: viewContext)
        counts["ProjectTemplateWeek"] = safeFetchCount(ProjectTemplateWeek.self, using: viewContext)
        counts["ProjectWeekRoleAssignment"] = safeFetchCount(ProjectWeekRoleAssignment.self, using: viewContext)

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

    /// Formats a byte count as a human-readable string.
    ///
    /// - Parameter bytes: The number of bytes
    /// - Returns: Human-readable string (e.g., "1.5 MB")
    static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Actual Size Measurement

    /// Measures the actual backup size by performing a dry-run export.
    /// This provides accurate size instead of estimation.
    ///
    /// - Parameters:
    ///   - viewContext: The model context to backup
    ///   - compress: Whether to apply compression
    /// - Returns: The actual size in bytes
    @MainActor
    static func measureActualSize(
        viewContext: NSManagedObjectContext,
        compress: Bool = true
    ) async throws -> ActualSizeMeasurement {
        let backupService = BackupService()

        // Create temporary URL for dry-run
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SizeMeasure-\(UUID().uuidString).\(BackupFile.fileExtension)")

        defer {
            // Clean up temp file
            do {
                try FileManager.default.removeItem(at: tempURL)
            } catch {
                logger.warning("Failed to remove temp file: \(error)")
            }
        }

        // Perform actual export to measure size
        _ = try await backupService.exportBackup(
            viewContext: viewContext,
            to: tempURL,
            password: nil,
            progress: { _, _ in }
        )

        // Get actual file size
        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Read the file to get entity counts
        let data = try Data(contentsOf: tempURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)

        // Calculate uncompressed size (estimate)
        let uncompressedEstimate = estimateFromCounts(envelope.manifest.entityCounts)
        let actualCompressionRatio = fileSize > 0 ? Double(uncompressedEstimate) / Double(fileSize) : 1.0

        return ActualSizeMeasurement(
            compressedSize: fileSize,
            uncompressedEstimate: uncompressedEstimate,
            entityCounts: envelope.manifest.entityCounts,
            compressionRatio: actualCompressionRatio,
            measurementDate: Date()
        )
    }

    /// Result of actual size measurement
    struct ActualSizeMeasurement: Sendable {
        let compressedSize: Int64
        let uncompressedEstimate: Int64
        let entityCounts: [String: Int]
        let compressionRatio: Double
        let measurementDate: Date

        var formattedCompressedSize: String {
            BackupSizeEstimator.formatSize(compressedSize)
        }

        var formattedUncompressedSize: String {
            BackupSizeEstimator.formatSize(uncompressedEstimate)
        }

        var totalEntityCount: Int {
            entityCounts.values.reduce(0, +)
        }
    }

    // MARK: - Private Helpers

    private static func safeFetchCount<T: NSManagedObject>(_ type: T.Type, using context: NSManagedObjectContext) -> Int {
        let descriptor = T.fetchRequest() as! NSFetchRequest<T>
        do {
            return try context.count(for: descriptor)
        } catch {
            logger.warning("Failed to fetch count for \(T.self): \(error)")
            return 0
        }
    }
}
