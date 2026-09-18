import Foundation
import CoreData
import SwiftUI
import CryptoKit
import Compression

public final class BackupService {
    /// Progress callback type for backup operations.
    /// Guaranteed to run on MainActor so callers can update UI state directly.
    public typealias ProgressCallback = @MainActor @Sendable (Double, String) -> Void

    public enum RestoreMode: String, CaseIterable, Identifiable, Codable, Sendable {
        case merge
        case replace
        public var id: String { rawValue }
    }

    public init() {}

    // MARK: - Size Estimation

    /// Estimates the backup size in bytes based on current entity counts.
    /// Delegates to BackupSizeEstimator for the actual calculation.
    public func estimateBackupSize(viewContext: NSManagedObjectContext) -> Int64 {
        BackupSizeEstimator.estimateBackupSize(viewContext: viewContext)
    }

}
