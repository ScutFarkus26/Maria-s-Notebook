// BackupIntegrityMonitor.swift
// Monitors backup health and integrity

import Foundation
import SwiftUI
import Combine

/// Monitors backup integrity and provides health status
@MainActor
public final class BackupIntegrityMonitor: ObservableObject {

    // MARK: - Types

    public enum BackupHealth: Sendable {
        case healthy
        case warning(String)
        case critical(String)

        public var isHealthy: Bool {
            if case .healthy = self { return true }
            return false
        }

        public var message: String? {
            switch self {
            case .healthy: return nil
            case .warning(let msg), .critical(let msg): return msg
            }
        }

        public var icon: String {
            switch self {
            case .healthy: return "checkmark.shield.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.shield.fill"
            }
        }

        public var color: Color {
            switch self {
            case .healthy: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }

    public struct IntegrityReport: Sendable {
        public let timestamp: Date
        public let health: BackupHealth
        public let totalBackups: Int
        public let healthyBackups: Int
        public let corruptedBackups: Int
        public let lastBackupDate: Date?
        public let daysSinceLastBackup: Int?
        public let oldestBackupDate: Date?
        public let totalBackupSize: Int64
        public let issues: [String]
        public let recommendations: [String]

        public var formattedTotalSize: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            return formatter.string(fromByteCount: totalBackupSize)
        }
    }

    public struct BackupVerificationResult: Identifiable, Sendable {
        public let id: UUID
        public let url: URL
        public let fileName: String
        public let isValid: Bool
        public let errorMessage: String?
        public let checksumValid: Bool?
        public let formatVersion: Int?
        public let createdAt: Date?
        public let fileSize: Int64
    }

    // MARK: - Published State

    @Published private(set) var latestReport: IntegrityReport?
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?

    // MARK: - Settings

    @AppStorage("BackupIntegrity.autoVerifyEnabled") private var autoVerifyEnabled = true
    @AppStorage("BackupIntegrity.warningDaysThreshold") private var warningDaysThreshold = 7

    // MARK: - Properties

    private let codec = BackupCodec()

    // MARK: - Public API

    /// Performs a full integrity scan of all backups
    public func performIntegrityScan() async -> IntegrityReport {
        isScanning = true
        defer {
            isScanning = false
            lastScanDate = Date()
        }

        var issues: [String] = []
        var recommendations: [String] = []

        // Scan auto-backup directory
        let autoBackupDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto")

        let verificationResults = await verifyBackupsInDirectory(autoBackupDir)

        let totalBackups = verificationResults.count
        let healthyBackups = verificationResults.filter { $0.isValid }.count
        let corruptedBackups = verificationResults.filter { !$0.isValid }.count

        // Calculate dates
        let sortedByDate = verificationResults
            .compactMap { $0.createdAt }
            .sorted(by: >)
        let lastBackupDate = sortedByDate.first
        let oldestBackupDate = sortedByDate.last

        let daysSinceLastBackup: Int?
        if let lastDate = lastBackupDate {
            daysSinceLastBackup = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day
        } else {
            daysSinceLastBackup = nil
        }

        // Calculate total size
        let totalSize = verificationResults.reduce(0) { $0 + $1.fileSize }

        // Analyze issues
        if totalBackups == 0 {
            issues.append("No automatic backups found.")
            recommendations.append("Enable automatic backups in Settings to protect your data.")
        }

        if corruptedBackups > 0 {
            issues.append("\(corruptedBackups) backup(s) failed integrity verification.")
            recommendations.append("Delete corrupted backups and create a new backup.")
        }

        if let days = daysSinceLastBackup, days > warningDaysThreshold {
            issues.append("Last backup is \(days) days old.")
            recommendations.append("Create a new backup to ensure recent data is protected.")
        }

        // Add specific error messages from corrupted backups
        for result in verificationResults where !result.isValid {
            if let error = result.errorMessage {
                issues.append("\(result.fileName): \(error)")
            }
        }

        // Determine overall health
        let health: BackupHealth
        if corruptedBackups > 0 {
            health = .critical("Found \(corruptedBackups) corrupted backup(s)")
        } else if let days = daysSinceLastBackup, days > warningDaysThreshold {
            health = .warning("Last backup is \(days) days old")
        } else if totalBackups == 0 {
            health = .warning("No backups found")
        } else {
            health = .healthy
        }

        let report = IntegrityReport(
            timestamp: Date(),
            health: health,
            totalBackups: totalBackups,
            healthyBackups: healthyBackups,
            corruptedBackups: corruptedBackups,
            lastBackupDate: lastBackupDate,
            daysSinceLastBackup: daysSinceLastBackup,
            oldestBackupDate: oldestBackupDate,
            totalBackupSize: totalSize,
            issues: issues,
            recommendations: recommendations
        )

        latestReport = report
        return report
    }

    /// Verifies a single backup file
    public func verifyBackup(at url: URL) async -> BackupVerificationResult {
        let fm = FileManager.default

        // Get file size
        let fileSize: Int64
        if let attributes = try? fm.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        // Attempt to verify the backup
        let result = BackupVerification.verifyBackup(at: url)

        switch result {
        case .success(let info):
            // Additionally verify checksum if possible
            let checksumValid = await verifyChecksum(at: url, expectedChecksum: info.checksum)

            return BackupVerificationResult(
                id: UUID(),
                url: url,
                fileName: url.lastPathComponent,
                isValid: checksumValid ?? true,
                errorMessage: checksumValid == false ? "Checksum mismatch" : nil,
                checksumValid: checksumValid,
                formatVersion: info.formatVersion,
                createdAt: info.createdAt,
                fileSize: fileSize
            )

        case .failure(let error):
            return BackupVerificationResult(
                id: UUID(),
                url: url,
                fileName: url.lastPathComponent,
                isValid: false,
                errorMessage: error.localizedDescription,
                checksumValid: nil,
                formatVersion: nil,
                createdAt: nil,
                fileSize: fileSize
            )
        }
    }

    /// Verifies all backups in a directory
    public func verifyBackupsInDirectory(_ directory: URL) async -> [BackupVerificationResult] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: directory.path) else {
            return []
        }

        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let backupFiles = files.filter { $0.pathExtension == BackupFile.fileExtension }

        var results: [BackupVerificationResult] = []

        for file in backupFiles {
            let result = await verifyBackup(at: file)
            results.append(result)
        }

        return results
    }

    /// Deletes corrupted backups
    public func deleteCorruptedBackups() async throws -> Int {
        let autoBackupDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto")

        let results = await verifyBackupsInDirectory(autoBackupDir)
        let corruptedFiles = results.filter { !$0.isValid }

        var deletedCount = 0
        for file in corruptedFiles {
            do {
                try FileManager.default.removeItem(at: file.url)
                deletedCount += 1
            } catch {
                #if DEBUG
                print("BackupIntegrityMonitor: Failed to delete \(file.fileName): \(error)")
                #endif
            }
        }

        // Refresh report after deletion
        _ = await performIntegrityScan()

        return deletedCount
    }

    // MARK: - Settings Access

    var isAutoVerifyEnabled: Bool {
        get { autoVerifyEnabled }
        set { autoVerifyEnabled = newValue }
    }

    var backupWarningDaysThreshold: Int {
        get { warningDaysThreshold }
        set { warningDaysThreshold = max(1, min(newValue, 30)) }
    }

    // MARK: - Private Helpers

    private func verifyChecksum(at url: URL, expectedChecksum: String) async -> Bool? {
        guard !expectedChecksum.isEmpty else { return nil }

        // Read the file and extract payload to verify checksum
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let envelope = try? decoder.decode(BackupEnvelope.self, from: data) else {
            return nil
        }

        // Get payload bytes
        let payloadBytes: Data?

        if envelope.payload != nil {
            // For unencrypted, uncompressed backups
            if let payloadData = try? BackupPayloadExtractor.extractPayloadBytes(from: data) {
                payloadBytes = payloadData
            } else {
                return nil
            }
        } else if let compressed = envelope.compressedPayload {
            // For compressed backups
            payloadBytes = try? codec.decompress(compressed)
        } else if envelope.encryptedPayload != nil {
            // Can't verify encrypted backups without password
            return nil
        } else {
            return nil
        }

        guard let bytes = payloadBytes else { return nil }

        let computedChecksum = codec.sha256Hex(bytes)
        return computedChecksum == expectedChecksum
    }
}

// MARK: - Quick Health Check Extension

extension BackupIntegrityMonitor {
    /// Performs a quick health check without deep verification
    public func quickHealthCheck() async -> BackupHealth {
        let status = BackupVerification.getBackupStatus()

        guard status.autoBackupDirectoryExists else {
            return .warning("No backup directory found")
        }

        guard let lastBackupURL = status.mostRecentAutoBackupURL else {
            return .warning("No backups found")
        }

        // Check age of most recent backup
        if let attributes = try? FileManager.default.attributesOfItem(atPath: lastBackupURL.path),
           let modDate = attributes[.modificationDate] as? Date {
            let daysSince = Calendar.current.dateComponents([.day], from: modDate, to: Date()).day ?? 0

            if daysSince > warningDaysThreshold {
                return .warning("Last backup is \(daysSince) days old")
            }
        }

        return .healthy
    }
}
