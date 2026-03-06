// IncrementalBackupService.swift
// Handles incremental backups that only export changed entities

import Foundation
import SwiftData

/// Service for creating incremental backups that only include entities
/// modified since the last backup, reducing backup size and time.
@MainActor
public final class IncrementalBackupService {

    // MARK: - Types

    public struct IncrementalBackupMetadata: Codable, Sendable {
        public var lastBackupDate: Date
        public var backupID: UUID
        public var parentBackupID: UUID?
        public var isFullBackup: Bool
        public var changedEntityCounts: [String: Int]

        public init(
            lastBackupDate: Date,
            backupID: UUID = UUID(),
            parentBackupID: UUID? = nil,
            isFullBackup: Bool,
            changedEntityCounts: [String: Int] = [:]
        ) {
            self.lastBackupDate = lastBackupDate
            self.backupID = backupID
            self.parentBackupID = parentBackupID
            self.isFullBackup = isFullBackup
            self.changedEntityCounts = changedEntityCounts
        }
    }

    public struct IncrementalBackupResult: Sendable {
        public let url: URL
        public let metadata: IncrementalBackupMetadata
        public let totalEntities: Int
        public let changedEntities: Int
        public let savedBytes: Int64
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastIncrementalBackupDate = "IncrementalBackup.lastDate"
        static let lastIncrementalBackupID = "IncrementalBackup.lastID"
    }

    // MARK: - Properties

    let backupService: BackupService
    let codec = BackupCodec()
    
    // MARK: - Initialization
    
    public init(backupService: BackupService) {
        self.backupService = backupService
    }

    /// The date of the last incremental backup
    public var lastBackupDate: Date? {
        let timestamp = UserDefaults.standard.double(forKey: Keys.lastIncrementalBackupDate)
        return timestamp > 0 ? Date(timeIntervalSinceReferenceDate: timestamp) : nil
    }

    /// The ID of the last incremental backup
    public var lastBackupID: UUID? {
        guard let string = UserDefaults.standard.string(forKey: Keys.lastIncrementalBackupID) else {
            return nil
        }
        return UUID(uuidString: string)
    }

    // MARK: - Public API

    /// Creates an incremental backup containing only entities changed since the last backup
    /// - Parameters:
    ///   - modelContext: The SwiftData model context
    ///   - url: Destination URL for the backup file
    ///   - password: Optional encryption password
    ///   - forceFullBackup: If true, creates a full backup regardless of last backup date
    ///   - progress: Progress callback
    /// - Returns: Result containing metadata and statistics
    public func createIncrementalBackup(
        modelContext: ModelContext,
        to url: URL,
        password: String? = nil,
        forceFullBackup: Bool = false,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> IncrementalBackupResult {

        let sinceDate = forceFullBackup ? nil : lastBackupDate
        let isFullBackup = sinceDate == nil

        progress(0.0, isFullBackup ? "Creating full backup…" : "Scanning for changes…")

        // Collect all entities and filter by updatedAt if incremental
        let collectionResult = try collectPayload(
            modelContext: modelContext,
            sinceDate: sinceDate,
            progress: { subProgress, message in
                progress(subProgress * 0.3, message)
            }
        )
        let payload = collectionResult.payload

        let changedCount = collectionResult.changedCounts.values.reduce(0, +)
        let totalCount = collectionResult.totalCounts.values.reduce(0, +)

        progress(0.3, "Encoding \(changedCount) entities…")

        // Encode payload
        let encoder = JSONEncoder.backupConfigured()
        let payloadBytes = try encoder.encode(payload)
        let sha = codec.sha256Hex(payloadBytes)

        progress(0.5, "Compressing data…")
        let compressedPayloadBytes = try codec.compress(payloadBytes)

        // Encrypt if password provided
        let finalPayload: BackupPayload?
        let finalEncrypted: Data?
        let finalCompressed: Data?

        if let password = password, !password.isEmpty {
            progress(0.6, "Encrypting data…")
            finalEncrypted = try codec.encrypt(compressedPayloadBytes, password: password)
            finalPayload = nil
            finalCompressed = nil
        } else {
            finalEncrypted = nil
            finalPayload = nil
            finalCompressed = compressedPayloadBytes
        }

        // Create metadata
        let backupID = UUID()
        let metadata = IncrementalBackupMetadata(
            lastBackupDate: Date(),
            backupID: backupID,
            parentBackupID: lastBackupID,
            isFullBackup: isFullBackup,
            changedEntityCounts: collectionResult.changedCounts
        )

        // Build envelope with incremental metadata in manifest notes
        let metadataJSON = try JSONEncoder().encode(metadata)
        let metadataString = String(data: metadataJSON, encoding: .utf8)

        let envelope = BackupServiceHelpers.buildEnvelope(
            payload: finalPayload,
            encryptedPayload: finalEncrypted,
            compressedPayload: finalCompressed,
            entityCounts: collectionResult.changedCounts,
            sha256: sha,
            notes: metadataString
        )

        progress(0.8, "Writing backup file…")
        try BackupServiceHelpers.writeBackupFile(envelope: envelope, to: url, encoder: encoder)

        // Update last backup tracking
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: Keys.lastIncrementalBackupDate)
        UserDefaults.standard.set(backupID.uuidString, forKey: Keys.lastIncrementalBackupID)

        progress(1.0, "Incremental backup complete")

        // Calculate saved bytes (estimate based on total vs changed)
        let estimatedFullSize = backupService.estimateBackupSizeFromCounts(collectionResult.totalCounts)
        let actualSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        let savedBytes = max(0, estimatedFullSize - actualSize)

        return IncrementalBackupResult(
            url: url,
            metadata: metadata,
            totalEntities: totalCount,
            changedEntities: changedCount,
            savedBytes: savedBytes
        )
    }

    /// Resets the incremental backup tracking (next backup will be full)
    public func resetIncrementalTracking() {
        UserDefaults.standard.removeObject(forKey: Keys.lastIncrementalBackupDate)
        UserDefaults.standard.removeObject(forKey: Keys.lastIncrementalBackupID)
    }

}
