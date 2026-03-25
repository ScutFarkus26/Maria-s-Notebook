// CloudBackupService+Scheduling.swift
// Scheduled cloud backup methods

import Foundation
import SwiftData
import OSLog

extension CloudBackupService {

    // MARK: - Scheduled Cloud Backups

    /// Starts scheduled cloud backups.
    ///
    /// - Parameter modelContext: The SwiftData model context to use for backups
    public func startScheduledBackups(modelContext: ModelContext) {
        self.scheduledModelContext = modelContext
        stopScheduledBackups()

        guard scheduleConfiguration.enabled && scheduleConfiguration.intervalHours > 0 else {
            return
        }

        // Load last backup date
        let timestamp = UserDefaults.standard.double(forKey: Keys.lastCloudBackupDate)
        if timestamp > 0 {
            lastCloudBackupDate = Date(timeIntervalSinceReferenceDate: timestamp)
        }

        scheduledBackupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                // Calculate time until next backup
                let intervalSeconds = TimeInterval(self.scheduleConfiguration.intervalHours * 3600)
                let nextBackupTime: Date

                if let lastBackup = self.lastCloudBackupDate {
                    nextBackupTime = lastBackup.addingTimeInterval(intervalSeconds)
                } else {
                    // First backup after interval from now
                    nextBackupTime = Date().addingTimeInterval(intervalSeconds)
                }

                self.nextScheduledBackupDate = nextBackupTime

                let waitTime = max(0, nextBackupTime.timeIntervalSinceNow)

                // Wait until next backup time
                if waitTime > 0 {
                    do {
                        try await Task.sleep(for: .seconds(waitTime))
                    } catch {
                        Logger.backup.warning("Task sleep interrupted: \(error.localizedDescription, privacy: .public)")
                    }
                }

                // Check if still enabled and not cancelled
                guard !Task.isCancelled, self.scheduleConfiguration.enabled else { break }

                // Perform scheduled backup
                await self.performScheduledCloudBackup()
            }
        }
    }

    /// Stops scheduled cloud backups.
    public func stopScheduledBackups() {
        scheduledBackupTask?.cancel()
        scheduledBackupTask = nil
        nextScheduledBackupDate = nil
    }

    /// Performs a scheduled cloud backup.
    func performScheduledCloudBackup() async {
        guard let modelContext = scheduledModelContext else { return }
        guard !isPerformingBackup else { return }

        isPerformingBackup = true
        defer { isPerformingBackup = false }

        do {
            let backupURL = try await exportToCloudWithRetry(
                modelContext: modelContext,
                password: nil,
                progress: { _, _ in }
            )

            // Update last backup date
            lastCloudBackupDate = Date()
            UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: Keys.lastCloudBackupDate)

            // Apply retention policy
            try await applyRetentionPolicy(maxCount: scheduleConfiguration.retentionCount)

            // Publish event using modern Observation pattern
            lastBackupEvent = CloudBackupEvent(
                timestamp: Date(),
                result: .completed(backupURL)
            )

        } catch {
            Logger.backup.error("Scheduled backup failed: \(error.localizedDescription)")

            // Publish event using modern Observation pattern
            lastBackupEvent = CloudBackupEvent(
                timestamp: Date(),
                result: .failed(error)
            )
        }
    }
}
