// BackupIntegrityMonitor.swift
// Monitors backup health and integrity

import Foundation
import OSLog

/// Monitors backup integrity and provides health status
@Observable
@MainActor
public final class BackupIntegrityMonitor {

    // MARK: - State

    private(set) var latestReport: IntegrityReport?
    private(set) var isScanning = false
    private(set) var lastScanDate: Date?
    var nextScheduledScanDate: Date?

    // MARK: - Settings (using UserDefaults since @AppStorage conflicts with @Observable)

    var autoVerifyEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "BackupIntegrity.autoVerifyEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "BackupIntegrity.autoVerifyEnabled") }
    }

    var scheduledVerificationEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "BackupIntegrity.scheduledVerificationEnabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "BackupIntegrity.scheduledVerificationEnabled") }
    }

    var verificationIntervalHours: Int {
        get { UserDefaults.standard.object(forKey: "BackupIntegrity.verificationIntervalHours") as? Int ?? 24 }
        set { UserDefaults.standard.set(newValue, forKey: "BackupIntegrity.verificationIntervalHours") }
    }

    var warningDaysThreshold: Int {
        get { UserDefaults.standard.object(forKey: "BackupIntegrity.warningDaysThreshold") as? Int ?? 7 }
        set { UserDefaults.standard.set(newValue, forKey: "BackupIntegrity.warningDaysThreshold") }
    }

    // MARK: - Properties

    let codec = BackupCodec()
    private let checksumService = ChecksumVerificationService()
    var scheduledVerificationTask: Task<Void, Never>?

    // MARK: - Initialization

    public init() {
        // Load last scan date from UserDefaults
        let timestamp = UserDefaults.standard.double(forKey: "BackupIntegrity.lastScanDate")
        if timestamp > 0 {
            lastScanDate = Date(timeIntervalSinceReferenceDate: timestamp)
        }
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

    var isScheduledVerificationEnabled: Bool {
        get { scheduledVerificationEnabled }
        set {
            scheduledVerificationEnabled = newValue
            if newValue {
                startScheduledVerification()
            } else {
                stopScheduledVerification()
            }
        }
    }

    var verificationInterval: Int {
        get { verificationIntervalHours }
        set {
            verificationIntervalHours = max(1, min(newValue, 168)) // Max 1 week
            // Restart scheduled verification with new interval
            if scheduledVerificationEnabled {
                startScheduledVerification()
            }
        }
    }

    // MARK: - Public API

    /// Performs a full integrity scan of all backups
    public func performIntegrityScan() async -> IntegrityReport {
        isScanning = true
        defer {
            isScanning = false
            lastScanDate = Date()
        }

        let autoBackupDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto")

        let verificationResults = await verifyBackupsInDirectory(autoBackupDir)
        let report = buildIntegrityReport(from: verificationResults)

        latestReport = report
        return report
    }

    private func buildIntegrityReport(from verificationResults: [BackupVerificationResult]) -> IntegrityReport {
        let totalBackups = verificationResults.count
        let healthyBackups = verificationResults.filter(\.isValid).count
        let corruptedBackups = verificationResults.filter { !$0.isValid }.count

        let sortedByDate = verificationResults.compactMap(\.createdAt).sorted(by: >)
        let lastBackupDate = sortedByDate.first
        let oldestBackupDate = sortedByDate.last
        let daysSinceLastBackup = lastBackupDate.flatMap {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day
        }

        let totalSize = verificationResults.reduce(0) { $0 + $1.fileSize }

        let (issues, recommendations) = analyzeIssues(
            verificationResults: verificationResults,
            totalBackups: totalBackups,
            corruptedBackups: corruptedBackups,
            daysSinceLastBackup: daysSinceLastBackup
        )

        let health = determineHealth(
            totalBackups: totalBackups,
            corruptedBackups: corruptedBackups,
            daysSinceLastBackup: daysSinceLastBackup
        )

        return IntegrityReport(
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
    }

    private func analyzeIssues(
        verificationResults: [BackupVerificationResult],
        totalBackups: Int,
        corruptedBackups: Int,
        daysSinceLastBackup: Int?
    ) -> (issues: [String], recommendations: [String]) {
        var issues: [String] = []
        var recommendations: [String] = []

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
        for result in verificationResults where !result.isValid {
            if let error = result.errorMessage {
                issues.append("\(result.fileName): \(error)")
            }
        }
        return (issues, recommendations)
    }

    private func determineHealth(
        totalBackups: Int,
        corruptedBackups: Int,
        daysSinceLastBackup: Int?
    ) -> BackupHealth {
        if corruptedBackups > 0 {
            return .critical("Found \(corruptedBackups) corrupted backup(s)")
        } else if let days = daysSinceLastBackup, days > warningDaysThreshold {
            return .warning("Last backup is \(days) days old")
        } else if totalBackups == 0 {
            return .warning("No backups found")
        } else {
            return .healthy
        }
    }

}

// MARK: - Verification

extension BackupIntegrityMonitor {

    /// Verifies a single backup file
    public func verifyBackup(at url: URL) async -> BackupVerificationResult {
        let fileSize = Self.fileSize(at: url)

        let result = BackupVerification.verifyBackup(at: url)

        switch result {
        case .success(let info):
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

        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            let dirName = directory.lastPathComponent
            let desc = error.localizedDescription
            Logger.backup.warning("Failed to list directory \(dirName, privacy: .public): \(desc, privacy: .public)")
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
                Logger.backup.error("Failed to delete \(file.fileName): \(error)")
            }
        }

        _ = await performIntegrityScan()
        return deletedCount
    }

    /// Gets the file size at a URL, returning 0 on failure
    static func fileSize(at url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            let name = url.lastPathComponent
            let desc = error.localizedDescription
            Logger.backup.warning("Failed to get file size for \(name, privacy: .public): \(desc, privacy: .public)")
            return 0
        }
    }

    /// Verifies the checksum of a backup file against an expected value
    func verifyChecksum(at url: URL, expectedChecksum: String) async -> Bool? {
        guard !expectedChecksum.isEmpty else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Logger.backup.warning("Failed to read backup file: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let envelope: BackupEnvelope
        do {
            envelope = try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            Logger.backup.warning("Failed to decode backup envelope: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let payloadBytes: Data?

        if envelope.payload != nil {
            do {
                payloadBytes = try BackupPayloadExtractor.extractPayloadBytes(from: data)
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to extract payload bytes: \(desc, privacy: .public)")
                return nil
            }
        } else if let compressed = envelope.compressedPayload {
            do {
                payloadBytes = try codec.decompress(compressed)
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to decompress payload: \(desc, privacy: .public)")
                return nil
            }
        } else if envelope.encryptedPayload != nil {
            return nil
        } else {
            return nil
        }

        guard let bytes = payloadBytes else { return nil }

        let computedChecksum = codec.sha256Hex(bytes)
        return computedChecksum == expectedChecksum
    }
}
