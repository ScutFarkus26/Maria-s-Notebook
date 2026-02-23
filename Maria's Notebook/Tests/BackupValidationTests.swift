// BackupValidationTests.swift
// Tests for backup validation and integrity checking

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - BackupIntegrityMonitor Tests

@Suite("BackupIntegrityMonitor Tests")
struct BackupIntegrityMonitorTests {

    @Test("Backup health enum properties")
    func testBackupHealthProperties() {
        let healthy = BackupIntegrityMonitor.BackupHealth.healthy
        let warning = BackupIntegrityMonitor.BackupHealth.warning("Old backup")
        let critical = BackupIntegrityMonitor.BackupHealth.critical("Corrupted")

        #expect(healthy.isHealthy == true)
        #expect(warning.isHealthy == false)
        #expect(critical.isHealthy == false)

        #expect(healthy.message == nil)
        #expect(warning.message == "Old backup")
        #expect(critical.message == "Corrupted")

        #expect(healthy.icon == "checkmark.shield.fill")
        #expect(warning.icon == "exclamationmark.triangle.fill")
        #expect(critical.icon == "xmark.shield.fill")
    }

    @Test("Integrity report structure")
    func testIntegrityReportStructure() {
        let report = BackupIntegrityMonitor.IntegrityReport(
            timestamp: Date(),
            health: .healthy,
            totalBackups: 5,
            healthyBackups: 5,
            corruptedBackups: 0,
            lastBackupDate: Date(),
            daysSinceLastBackup: 1,
            oldestBackupDate: Date().addingTimeInterval(-86400 * 30),
            totalBackupSize: 10 * 1024 * 1024, // 10 MB
            issues: [],
            recommendations: []
        )

        #expect(report.totalBackups == 5)
        #expect(report.healthyBackups == 5)
        #expect(report.corruptedBackups == 0)
        #expect(report.daysSinceLastBackup == 1)
        #expect(report.formattedTotalSize.contains("MB"))
    }

    @Test("Verification result structure")
    func testVerificationResultStructure() {
        let result = BackupIntegrityMonitor.BackupVerificationResult(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/test.mtbbackup"),
            fileName: "test.mtbbackup",
            isValid: true,
            errorMessage: nil,
            checksumValid: true,
            formatVersion: 6,
            createdAt: Date(),
            fileSize: 1024
        )

        #expect(result.isValid == true)
        #expect(result.errorMessage == nil)
        #expect(result.checksumValid == true)
        #expect(result.formatVersion == 6)
    }

    @Test("Quick health check on missing directory")
    @MainActor
    func testQuickHealthCheckMissingDirectory() async {
        let monitor = BackupIntegrityMonitor()

        // This tests the quick health check functionality
        let health = await monitor.quickHealthCheck()

        // Should return warning or healthy depending on backup state
        // Just verify it doesn't crash and returns a valid result
        let _ = health.isHealthy
        let _ = health.message
    }

    @Test("Backup health healthy state")
    func testBackupHealthHealthyState() {
        let health = BackupIntegrityMonitor.BackupHealth.healthy
        
        #expect(health.isHealthy)
        #expect(health.message == nil)
        #expect(health.icon == "checkmark.shield.fill")
    }

    @Test("Backup health warning state with message")
    func testBackupHealthWarningState() {
        let warningMessage = "Backup is 7 days old"
        let health = BackupIntegrityMonitor.BackupHealth.warning(warningMessage)
        
        #expect(!health.isHealthy)
        #expect(health.message == warningMessage)
        #expect(health.icon == "exclamationmark.triangle.fill")
    }

    @Test("Backup health critical state with message")
    func testBackupHealthCriticalState() {
        let criticalMessage = "Backup file is corrupted"
        let health = BackupIntegrityMonitor.BackupHealth.critical(criticalMessage)
        
        #expect(!health.isHealthy)
        #expect(health.message == criticalMessage)
        #expect(health.icon == "xmark.shield.fill")
    }

    @Test("Integrity report with issues")
    func testIntegrityReportWithIssues() {
        let issues = ["Corrupted backup detected", "Missing checksum"]
        let recommendations = ["Delete corrupted backup", "Run verification"]
        
        let report = BackupIntegrityMonitor.IntegrityReport(
            timestamp: Date(),
            health: .critical("Multiple issues"),
            totalBackups: 3,
            healthyBackups: 1,
            corruptedBackups: 2,
            lastBackupDate: Date(),
            daysSinceLastBackup: 0,
            oldestBackupDate: Date().addingTimeInterval(-86400 * 60),
            totalBackupSize: 5 * 1024 * 1024,
            issues: issues,
            recommendations: recommendations
        )
        
        #expect(report.issues.count == 2)
        #expect(report.recommendations.count == 2)
        #expect(report.corruptedBackups == 2)
        #expect(!report.health.isHealthy)
    }

    @Test("Verification result for invalid backup")
    func testVerificationResultInvalid() {
        let result = BackupIntegrityMonitor.BackupVerificationResult(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/corrupt.mtbbackup"),
            fileName: "corrupt.mtbbackup",
            isValid: false,
            errorMessage: "Checksum mismatch",
            checksumValid: false,
            formatVersion: 0,
            createdAt: nil,
            fileSize: 1024
        )
        
        #expect(!result.isValid)
        #expect(result.errorMessage != nil)
        #expect(result.checksumValid == false)
        #expect(result.createdAt == nil)
    }
}

// MARK: - BackupMigrationManifest Tests

@Suite("BackupMigrationManifest Tests")
struct BackupMigrationManifestTests {

    @Test("Current version matches BackupFile")
    func testCurrentVersionMatches() {
        #expect(BackupMigrationManifest.currentVersion == BackupFile.formatVersion)
    }

    @Test("Version history is not empty")
    func testVersionHistoryNotEmpty() {
        #expect(!BackupMigrationManifest.versionHistory.isEmpty)
    }

    @Test("Version history contains current version")
    func testVersionHistoryContainsCurrent() {
        let current = BackupMigrationManifest.currentVersion
        let hasCurrentVersion = BackupMigrationManifest.versionHistory.contains { $0.version == current }
        #expect(hasCurrentVersion)
    }

    @Test("Version info retrieval")
    func testVersionInfoRetrieval() {
        let info = BackupMigrationManifest.info(for: 6)
        #expect(info != nil)
        #expect(info?.version == 6)
        #expect(!info!.description.isEmpty)
    }

    @Test("Version info for invalid version returns nil")
    func testVersionInfoInvalid() {
        let info = BackupMigrationManifest.info(for: 999)
        #expect(info == nil)
    }

    @Test("Version compatibility for current")
    func testVersionCompatibilityCurrent() {
        let compatibility = BackupMigrationManifest.isCompatible(version: BackupMigrationManifest.currentVersion)
        #expect(compatibility.isCompatible)
    }

    @Test("Version compatibility for future")
    func testVersionCompatibilityFuture() {
        let futureVersion = BackupMigrationManifest.currentVersion + 10
        let compatibility = BackupMigrationManifest.isCompatible(version: futureVersion)

        if case .futureVersion(let v) = compatibility {
            #expect(v == futureVersion)
        } else {
            Issue.record("Expected futureVersion case")
        }
    }

    @Test("Version compatibility for invalid")
    func testVersionCompatibilityInvalid() {
        let compatibility = BackupMigrationManifest.isCompatible(version: 0)

        if case .invalid = compatibility {
            // Expected
        } else {
            Issue.record("Expected invalid case")
        }
    }

    @Test("Payload fields documentation exists")
    func testPayloadFieldsDocumentation() {
        #expect(!BackupMigrationManifest.payloadFields.isEmpty)

        // Check that essential fields are documented
        let fieldNames = Set(BackupMigrationManifest.payloadFields.map { $0.name })
        #expect(fieldNames.contains("students"))
        #expect(fieldNames.contains("lessons"))
        #expect(fieldNames.contains("preferences"))
    }

    @Test("Payload field version ranges")
    func testPayloadFieldVersionRanges() {
        for field in BackupMigrationManifest.payloadFields {
            #expect(field.introducedIn >= 1)
            if let removed = field.removedIn {
                #expect(removed > field.introducedIn)
            }
            #expect(!field.versionRange.isEmpty)
        }
    }

    @Test("Entity schema changes documentation")
    func testEntitySchemaChangesDocumentation() {
        #expect(!BackupMigrationManifest.EntitySchemaChanges.studentChanges.isEmpty)
        #expect(!BackupMigrationManifest.EntitySchemaChanges.lessonChanges.isEmpty)
        #expect(!BackupMigrationManifest.EntitySchemaChanges.noteChanges.isEmpty)
        #expect(!BackupMigrationManifest.EntitySchemaChanges.projectChanges.isEmpty)
    }

    @Test("Format version info properties")
    func testFormatVersionInfoProperties() {
        guard let info = BackupMigrationManifest.info(for: 6) else {
            Issue.record("Version 6 info not found")
            return
        }

        #expect(info.id == 6)
        #expect(info.version == 6)
        #expect(!info.description.isEmpty)
        #expect(!info.changes.isEmpty)
        #expect(!info.formattedReleaseDate.isEmpty)
    }

    @Test("Version history is sorted by version")
    func testVersionHistorySorted() {
        let versions = BackupMigrationManifest.versionHistory.map { $0.version }
        let sortedVersions = versions.sorted()
        #expect(versions == sortedVersions)
    }

    @Test("All versions have unique version numbers")
    func testVersionHistoryUnique() {
        let versions = BackupMigrationManifest.versionHistory.map { $0.version }
        let uniqueVersions = Set(versions)
        #expect(versions.count == uniqueVersions.count)
    }
}

// MARK: - BackupNotificationService Tests

@Suite("BackupNotificationService Tests")
struct BackupNotificationServiceTests {

    @Test("Notification type properties")
    func testNotificationTypeProperties() {
        for type in BackupNotificationService.NotificationType.allCases {
            #expect(!type.rawValue.isEmpty)
            #expect(!type.systemImage.isEmpty)
        }

        #expect(BackupNotificationService.NotificationType.autoBackupFailed.isError == true)
        #expect(BackupNotificationService.NotificationType.backupIntegrityIssue.isError == true)
        #expect(BackupNotificationService.NotificationType.autoBackupComplete.isError == false)
    }

    @Test("Backup notification structure")
    func testBackupNotificationStructure() {
        let notification = BackupNotificationService.BackupNotification(
            type: .autoBackupComplete,
            title: "Backup Complete",
            message: "Your backup was successful",
            backupURL: URL(fileURLWithPath: "/tmp/backup.mtbbackup")
        )

        #expect(notification.title == "Backup Complete")
        #expect(notification.message == "Your backup was successful")
        #expect(notification.backupURL != nil)
        #expect(notification.isRead == false)
        #expect(notification.type == .autoBackupComplete)
    }

    @Test("Health badge properties")
    func testHealthBadgeProperties() {
        let healthyBadge = BackupNotificationService.BackupHealthBadge(
            isHealthy: true,
            warningCount: 0,
            lastBackupDate: Date(),
            message: nil
        )

        #expect(healthyBadge.badgeColor == "green")
        #expect(healthyBadge.systemImage == "checkmark.shield.fill")
        #expect(healthyBadge.statusText == "Healthy")

        let warningBadge = BackupNotificationService.BackupHealthBadge(
            isHealthy: true,
            warningCount: 2,
            lastBackupDate: Date(),
            message: "Some warnings"
        )

        #expect(warningBadge.badgeColor == "orange")
        #expect(warningBadge.statusText == "2 Warning(s)")

        let unhealthyBadge = BackupNotificationService.BackupHealthBadge(
            isHealthy: false,
            warningCount: 0,
            lastBackupDate: nil,
            message: "Critical issue"
        )

        #expect(unhealthyBadge.badgeColor == "red")
        #expect(unhealthyBadge.statusText == "Issues Detected")
    }

    @Test("Notification service settings defaults")
    @MainActor
    func testNotificationServiceSettingsDefaults() async {
        let service = BackupNotificationService()

        // Access settings - should not crash
        let _ = service.notificationsEnabled
        let _ = service.showSuccessNotifications
        let _ = service.showFailureNotifications
        let _ = service.showHealthWarnings
    }

    @Test("Clear notifications")
    @MainActor
    func testClearNotifications() async {
        let service = BackupNotificationService()

        // Add some state
        service.clearNotifications()

        #expect(service.recentNotifications.isEmpty)
        #expect(service.unreadCount == 0)
    }

    @Test("Health badge with no backups")
    func testHealthBadgeNoBackups() {
        let badge = BackupNotificationService.BackupHealthBadge(
            isHealthy: false,
            warningCount: 0,
            lastBackupDate: nil,
            message: "No backups found"
        )

        #expect(!badge.isHealthy)
        #expect(badge.badgeColor == "red")
        #expect(badge.lastBackupDate == nil)
    }

    @Test("Notification type error classification")
    func testNotificationTypeErrorClassification() {
        let errorTypes: [BackupNotificationService.NotificationType] = [
            .autoBackupFailed,
            .backupIntegrityIssue
        ]

        for type in errorTypes {
            #expect(type.isError, "Type \(type.rawValue) should be marked as error")
        }

        let successTypes: [BackupNotificationService.NotificationType] = [
            .autoBackupComplete
        ]

        for type in successTypes {
            #expect(!type.isError, "Type \(type.rawValue) should not be marked as error")
        }
    }
}
#endif
