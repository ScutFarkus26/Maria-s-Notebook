import Foundation
import CoreData
import SwiftUI
import CryptoKit
import Compression

@MainActor
public final class BackupService {
    /// Progress callback type for backup operations.
    /// Guaranteed to run on MainActor so callers can update UI state directly.
    public typealias ProgressCallback = @MainActor @Sendable (Double, String) -> Void

    public enum RestoreMode: String, CaseIterable, Identifiable, Codable, Sendable {
        case merge
        case replace
        public var id: String { rawValue }
    }

    let codec = BackupCodec()

    public init() {}

    // MARK: - Size Estimation

    /// Estimates the backup size in bytes based on current entity counts.
    /// Delegates to BackupSizeEstimator for the actual calculation.
    public func estimateBackupSize(viewContext: NSManagedObjectContext) -> Int64 {
        BackupSizeEstimator.estimateBackupSize(viewContext: viewContext)
    }

    /// Estimates backup size from entity counts dictionary.
    /// Delegates to BackupSizeEstimator for the actual calculation.
    public func estimateBackupSizeFromCounts(_ counts: [String: Int]) -> Int64 {
        BackupSizeEstimator.estimateFromCounts(counts)
    }

    // MARK: - Export
    public func exportBackup(
        viewContext: NSManagedObjectContext,
        to url: URL,
        password: String? = nil,
        progress: @escaping ProgressCallback
    ) async throws -> BackupOperationSummary {
        return try withSecurityScopedResource(url) {
            try performExport(viewContext: viewContext, to: url, password: password, progress: progress)
        }
    }
}
