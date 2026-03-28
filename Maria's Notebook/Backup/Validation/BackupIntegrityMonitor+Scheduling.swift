import Foundation
import OSLog

// MARK: - Scheduled Verification

extension BackupIntegrityMonitor {

    /// Starts scheduled verification of backup integrity
    public func startScheduledVerification() {
        stopScheduledVerification()

        guard scheduledVerificationEnabled && verificationIntervalHours > 0 else { return }

        scheduledVerificationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                // Calculate time until next scan
                let intervalSeconds = TimeInterval(self.verificationIntervalHours * 3600)
                let nextScanTime: Date

                if let lastScan = self.lastScanDate {
                    nextScanTime = lastScan.addingTimeInterval(intervalSeconds)
                } else {
                    nextScanTime = Date().addingTimeInterval(intervalSeconds)
                }

                self.nextScheduledScanDate = nextScanTime

                let waitTime = max(0, nextScanTime.timeIntervalSinceNow)

                if waitTime > 0 {
                    do {
                        try await Task.sleep(for: .seconds(waitTime))
                    } catch {
                        Logger.backup.warning(
                            "Task sleep interrupted: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }

                guard !Task.isCancelled, self.scheduledVerificationEnabled else { break }

                await self.performScheduledScan()
            }
        }
    }

    /// Stops scheduled verification
    public func stopScheduledVerification() {
        scheduledVerificationTask?.cancel()
        scheduledVerificationTask = nil
        nextScheduledScanDate = nil
    }

    /// Performs a scheduled integrity scan
    func performScheduledScan() async {
        let report = await performIntegrityScan()

        UserDefaults.standard.set(
            Date().timeIntervalSinceReferenceDate,
            forKey: "BackupIntegrity.lastScanDate"
        )

        if !report.health.isHealthy {
            NotificationCenter.default.post(
                name: .backupIntegrityIssuesDetected,
                object: self,
                userInfo: ["report": report]
            )
        }

        Logger.backup.info("Scheduled scan complete. Health: \(report.health)")
    }
}
