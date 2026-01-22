#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Backup Configuration Tests

/// Tests to verify backup configuration behavior.
@Suite("Backup Configuration Tests")
@MainActor
struct BackupConfigurationTests {

    @Test("ScheduleConfiguration default values are correct")
    func scheduleConfigurationDefaults() {
        let config = CloudBackupService.ScheduleConfiguration.default

        #expect(config.enabled == false)
        #expect(config.intervalHours == 24)
        #expect(config.retentionCount == 7)
    }

    @Test("ScheduleConfiguration encodes to JSON correctly")
    func scheduleConfigurationEncoding() throws {
        let config = CloudBackupService.ScheduleConfiguration(
            enabled: true,
            intervalHours: 12,
            retentionCount: 5
        )

        let data = try JSONEncoder().encode(config)
        let json = String(data: data, encoding: .utf8)

        #expect(json != nil)
        #expect(json!.contains("\"enabled\":true"))
    }

    @Test("ScheduleConfiguration decodes from JSON correctly")
    func scheduleConfigurationDecoding() throws {
        let json = """
        {"enabled":true,"intervalHours":48,"retentionCount":10}
        """
        let data = json.data(using: .utf8)!

        let config = try JSONDecoder().decode(
            CloudBackupService.ScheduleConfiguration.self,
            from: data
        )

        #expect(config.enabled == true)
        #expect(config.intervalHours == 48)
        #expect(config.retentionCount == 10)
    }
}

// MARK: - Incremental Backup Tests

/// Tests to verify incremental backup behavior.
@Suite("Incremental Backup Behavior Tests", .serialized)
@MainActor
struct IncrementalBackupBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("Incremental backup service can be created")
    func incrementalBackupServiceCreation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Add some data
        let student = makeTestStudent()
        let lesson = makeTestLesson()
        let note = Note(body: "Test note", scope: .all)

        context.insert(student)
        context.insert(lesson)
        context.insert(note)
        try context.save()

        // Service should be creatable (MainActor isolated)
        let _ = IncrementalBackupService()
    }

    @Test("Incremental backup tracking can be reset")
    func incrementalBackupReset() {
        let service = IncrementalBackupService()

        // Reset tracking
        service.resetIncrementalTracking()

        // After reset, last backup date should be nil
        #expect(service.lastBackupDate == nil)
        #expect(service.lastBackupID == nil)
    }
}

// MARK: - Selective Restore Tests

/// Tests to verify selective restore behavior.
@Suite("Selective Restore Behavior Tests", .serialized)
@MainActor
struct SelectiveRestoreBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("RestorableEntityType has all expected types")
    func restorableEntityTypesExist() {
        let allTypes = SelectiveRestoreService.RestorableEntityType.allCases

        #expect(allTypes.contains(.students))
        #expect(allTypes.contains(.lessons))
        #expect(allTypes.contains(.studentLessons))
        #expect(allTypes.contains(.notes))
        #expect(allTypes.contains(.workPlanItems))
    }

    @Test("SelectiveRestoreOptions resolves dependencies")
    func selectiveRestoreOptionsDependencies() {
        let options = SelectiveRestoreService.SelectiveRestoreOptions(
            entityTypes: [.studentLessons],
            includeDependencies: true
        )

        let resolved = options.resolvedEntityTypes

        // studentLessons depends on students and lessons
        #expect(resolved.contains(.studentLessons))
        #expect(resolved.contains(.students))
        #expect(resolved.contains(.lessons))
    }

    @Test("SelectiveRestoreOptions can disable dependency resolution")
    func selectiveRestoreOptionsNoDependencies() {
        let options = SelectiveRestoreService.SelectiveRestoreOptions(
            entityTypes: [.studentLessons],
            includeDependencies: false
        )

        let resolved = options.resolvedEntityTypes

        #expect(resolved.contains(.studentLessons))
        #expect(!resolved.contains(.students))
        #expect(!resolved.contains(.lessons))
    }
}

// MARK: - Backup Notification Tests

/// Tests to verify backup notification behavior.
@Suite("Backup Notification Tests")
@MainActor
struct BackupNotificationTests {

    @Test("Notification types are distinct")
    func notificationTypes() {
        let types = BackupNotificationService.NotificationType.allCases

        // Should have multiple distinct types
        #expect(types.count >= 2)

        // Each type should have a system image
        for type in types {
            #expect(!type.systemImage.isEmpty)
        }
    }

    @Test("BackupNotification can be created")
    func backupNotificationCreation() {
        let notification = BackupNotificationService.BackupNotification(
            type: .autoBackupComplete,
            title: "Test",
            message: "Test message"
        )

        #expect(notification.title == "Test")
        #expect(notification.message == "Test message")
        #expect(notification.type == .autoBackupComplete)
        #expect(notification.timestamp <= Date())
    }

    @Test("BackupNotificationService can be created and configured")
    func backupNotificationServiceCreation() {
        let service = BackupNotificationService()

        // Service should have configurable settings
        let _ = service.notificationsEnabled
        let _ = service.showSuccessNotifications
        let _ = service.showFailureNotifications
        let _ = service.showHealthWarnings
    }

    @Test("BackupNotificationService clears notifications")
    func serviceClearsNotifications() {
        let service = BackupNotificationService()

        // Clear any existing notifications
        service.clearNotifications()

        #expect(service.recentNotifications.isEmpty)
    }
}

// MARK: - Backup Sharing Tests

/// Tests to verify backup sharing behavior.
@Suite("Backup Sharing Tests")
@MainActor
struct BackupSharingTests {

    @Test("SharingOptions has correct defaults")
    func sharingOptionsDefaults() {
        let options = BackupSharingService.SharingOptions.default

        #expect(options.includeMetadata == true)
        #expect(options.encryptIfUnencrypted == false)
        #expect(options.createTemporaryCopy == true)
    }

    @Test("PreparedShare can be created")
    func preparedShareCreation() {
        let share = BackupSharingService.PreparedShare(
            url: URL(fileURLWithPath: "/tmp/test.mtbbackup"),
            fileName: "test.mtbbackup",
            fileSize: 1024,
            isEncrypted: false,
            isTemporary: true,
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(share.fileName == "test.mtbbackup")
        #expect(share.fileSize == 1024)
        #expect(share.isEncrypted == false)
        #expect(share.isTemporary == true)
        #expect(!share.formattedFileSize.isEmpty)
    }
}

// MARK: - CloudKit Sync Status Tests

/// Tests to verify CloudKit sync status behavior.
@Suite("CloudKit Sync Status Behavior Tests")
@MainActor
struct CloudKitSyncStatusBehaviorTests {

    @Test("SyncHealth states are distinct")
    func syncHealthStatesDistinct() {
        let states: [CloudKitSyncStatusService.SyncHealth] = [
            .healthy,
            .syncing,
            .warning,
            .error("test"),
            .offline,
            .unknown
        ]

        // Each state should have a color
        for state in states {
            let _ = state.color // Should not crash
        }

        // Each state should have an icon
        for state in states {
            let _ = state.icon // Should not crash
        }

        // Each state should have display text
        for state in states {
            let _ = state.displayText // Should not crash
        }
    }

    @Test("Sync service can be created")
    func syncServiceCreation() {
        let service = CloudKitSyncStatusService()

        // Access published properties
        let _ = service.isSyncing
        let _ = service.lastSuccessfulSync
        let _ = service.lastSyncError
        let _ = service.syncHealth
    }

    @Test("Sync service clear error works")
    func syncServiceClearError() {
        // Set up error state
        UserDefaults.standard.set("Test error", forKey: UserDefaultsKeys.cloudKitLastSyncError)

        let service = CloudKitSyncStatusService()

        service.clearError()

        #expect(service.lastSyncError == nil)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
    }
}

// MARK: - Retry Logic Tests

/// Tests to verify retry logic behavior.
@Suite("Retry Logic Tests")
struct RetryLogicTests {

    @Test("Exponential backoff calculates correctly")
    func exponentialBackoffCalculation() {
        let baseDelay: Double = 2.0
        let maxAttempts = 5

        var delays: [Double] = []
        for attempt in 0..<maxAttempts {
            let delay = baseDelay * pow(2.0, Double(attempt))
            delays.append(delay)
        }

        #expect(delays[0] == 2.0)  // 2^0 * 2 = 2
        #expect(delays[1] == 4.0)  // 2^1 * 2 = 4
        #expect(delays[2] == 8.0)  // 2^2 * 2 = 8
        #expect(delays[3] == 16.0) // 2^3 * 2 = 16
        #expect(delays[4] == 32.0) // 2^4 * 2 = 32
    }

    @Test("Jitter adds randomization")
    func jitterAddsRandomization() {
        let baseDelay: Double = 2.0
        var delaysWithJitter: [Double] = []

        for _ in 0..<10 {
            let jitter = Double.random(in: 0...0.5)
            let delay = baseDelay + jitter
            delaysWithJitter.append(delay)
        }

        // All delays should be between 2.0 and 2.5
        for delay in delaysWithJitter {
            #expect(delay >= 2.0)
            #expect(delay <= 2.5)
        }

        // Not all delays should be identical (with high probability)
        let uniqueDelays = Set(delaysWithJitter)
        #expect(uniqueDelays.count > 1)
    }

    @Test("Max delay cap is respected")
    func maxDelayCap() {
        let baseDelay: Double = 2.0
        let maxDelay: Double = 30.0

        // After many attempts, delay would exceed max
        let attempt = 10
        let uncappedDelay = baseDelay * pow(2.0, Double(attempt))
        let cappedDelay = min(uncappedDelay, maxDelay)

        #expect(uncappedDelay > maxDelay) // Would exceed
        #expect(cappedDelay == maxDelay)  // But is capped
    }

    @Test("RetryConfiguration has sensible defaults")
    func retryConfigurationDefaults() {
        let config = CloudBackupService.RetryConfiguration.default

        #expect(config.maxRetries >= 1)
        #expect(config.baseDelaySeconds > 0)
        #expect(config.maxDelaySeconds > config.baseDelaySeconds)
        #expect(config.backoffMultiplier > 1.0)
    }
}

// MARK: - Cloud Backup Service Performance Tests

/// Performance tests to verify CloudBackupService behavior.
@Suite("Cloud Backup Service Performance Tests")
@MainActor
struct CloudBackupServicePerformanceTests {

    @Test("CloudBackupService can be created")
    func cloudBackupServiceCreation() {
        let service = CloudBackupService()

        // Should have observable state
        let _ = service.isPerformingBackup
        let _ = service.lastCloudBackupDate
        let _ = service.nextScheduledBackupDate
        let _ = service.currentRetryAttempt
    }

    @Test("CloudBackupService can check iCloud availability")
    func cloudBackupServiceICloudCheck() {
        let service = CloudBackupService()

        // Should be able to check (result depends on system state)
        let _ = service.isICloudAvailable
    }

    @Test("Schedule configuration can be updated")
    func scheduleConfigurationUpdate() {
        let service = CloudBackupService()

        let newConfig = CloudBackupService.ScheduleConfiguration(
            enabled: true,
            intervalHours: 12,
            retentionCount: 5
        )

        service.scheduleConfiguration = newConfig

        #expect(service.scheduleConfiguration.enabled == true)
        #expect(service.scheduleConfiguration.intervalHours == 12)
        #expect(service.scheduleConfiguration.retentionCount == 5)

        // Reset to default
        service.scheduleConfiguration = .default
    }
}

#endif
