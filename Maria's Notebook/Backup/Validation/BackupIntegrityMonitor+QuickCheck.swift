// BackupIntegrityMonitor+QuickCheck.swift
// Quick health check for BackupIntegrityMonitor

import Foundation
import OSLog

// MARK: - Quick Health Check

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
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: lastBackupURL.path)
            if let modDate = attributes[.modificationDate] as? Date {
                let daysSince = Calendar.current.dateComponents([.day], from: modDate, to: Date()).day ?? 0

                if daysSince > warningDaysThreshold {
                    return .warning("Last backup is \(daysSince) days old")
                }
            }
        } catch {
            Logger.backup.warning(
                "Failed to get backup modification date: \(error.localizedDescription, privacy: .public)"
            )
        }

        return .healthy
    }
}
