import Foundation
import SwiftData
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
        "LegacyPresentation": 300,
        // WorkPlanItem removed in Phase 6 - migrated to WorkCheckIn
        "Note": 300,
        "NonSchoolDay": 200,
        "SchoolDayOverride": 200,
        "StudentMeeting": 1200,
        // Presentation removed - using LessonAssignment instead
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
    /// - Parameter modelContext: The model context to count entities from
    /// - Returns: Estimated compressed backup size in bytes
    static func estimateBackupSize(modelContext: ModelContext) -> Int64 {
        let counts = countEntities(modelContext: modelContext)
        return estimateFromCounts(counts)
    }

    /// Counts all exportable entities in the database.
    ///
    /// - Parameter modelContext: The model context to count entities from
    /// - Returns: Dictionary mapping entity type names to counts
    static func countEntities(modelContext: ModelContext) -> [String: Int] {
        var counts: [String: Int] = [:]

        counts["Student"] = safeFetchCount(Student.self, using: modelContext)
        counts["Lesson"] = safeFetchCount(Lesson.self, using: modelContext)
        // LegacyPresentation removed — fully migrated to LessonAssignment
        // WorkPlanItem removed in Phase 6 - migrated to WorkCheckIn
        counts["Note"] = safeFetchCount(Note.self, using: modelContext)
        counts["NonSchoolDay"] = safeFetchCount(NonSchoolDay.self, using: modelContext)
        counts["SchoolDayOverride"] = safeFetchCount(SchoolDayOverride.self, using: modelContext)
        counts["StudentMeeting"] = safeFetchCount(StudentMeeting.self, using: modelContext)
        // Presentation removed - using LessonAssignment instead
        counts["CommunityTopic"] = safeFetchCount(CommunityTopic.self, using: modelContext)
        counts["ProposedSolution"] = safeFetchCount(ProposedSolution.self, using: modelContext)
        counts["CommunityAttachment"] = safeFetchCount(CommunityAttachment.self, using: modelContext)
        counts["AttendanceRecord"] = safeFetchCount(AttendanceRecord.self, using: modelContext)
        counts["WorkCompletionRecord"] = safeFetchCount(WorkCompletionRecord.self, using: modelContext)
        counts["Project"] = safeFetchCount(Project.self, using: modelContext)
        counts["ProjectAssignmentTemplate"] = safeFetchCount(ProjectAssignmentTemplate.self, using: modelContext)
        counts["ProjectSession"] = safeFetchCount(ProjectSession.self, using: modelContext)
        counts["ProjectRole"] = safeFetchCount(ProjectRole.self, using: modelContext)
        counts["ProjectTemplateWeek"] = safeFetchCount(ProjectTemplateWeek.self, using: modelContext)
        counts["ProjectWeekRoleAssignment"] = safeFetchCount(ProjectWeekRoleAssignment.self, using: modelContext)

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
    ///   - modelContext: The model context to backup
    ///   - compress: Whether to apply compression
    /// - Returns: The actual size in bytes
    @MainActor
    static func measureActualSize(
        modelContext: ModelContext,
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
            modelContext: modelContext,
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

    private static func safeFetchCount<T: PersistentModel>(_ type: T.Type, using context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<T>()
        do {
            return try context.fetchCount(descriptor)
        } catch {
            logger.warning("Failed to fetch count for \(T.self): \(error)")
            return 0
        }
    }
}
