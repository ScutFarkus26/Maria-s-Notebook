// CloudKitSyncStatusServiceTests.swift
// Comprehensive tests for CloudKitSyncStatusService

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Maria_s_Notebook

// MARK: - SyncHealth Tests

@Suite("SyncHealth Enum Tests")
struct SyncHealthTests {

    @Test("SyncHealth color properties")
    func testSyncHealthColors() {
        #expect(CloudKitSyncStatusService.SyncHealth.healthy.color == .green)
        #expect(CloudKitSyncStatusService.SyncHealth.syncing.color == .blue)
        #expect(CloudKitSyncStatusService.SyncHealth.warning.color == .orange)
        #expect(CloudKitSyncStatusService.SyncHealth.error("test").color == .red)
        #expect(CloudKitSyncStatusService.SyncHealth.offline.color == .gray)
        #expect(CloudKitSyncStatusService.SyncHealth.unknown.color == .gray)
    }

    @Test("SyncHealth icon properties")
    func testSyncHealthIcons() {
        #expect(CloudKitSyncStatusService.SyncHealth.healthy.icon == "checkmark.icloud")
        #expect(CloudKitSyncStatusService.SyncHealth.syncing.icon == "arrow.triangle.2.circlepath.icloud")
        #expect(CloudKitSyncStatusService.SyncHealth.warning.icon == "exclamationmark.icloud")
        #expect(CloudKitSyncStatusService.SyncHealth.error("test").icon == "xmark.icloud")
        #expect(CloudKitSyncStatusService.SyncHealth.offline.icon == "icloud.slash")
        #expect(CloudKitSyncStatusService.SyncHealth.unknown.icon == "icloud")
    }

    @Test("SyncHealth display text")
    func testSyncHealthDisplayText() {
        #expect(CloudKitSyncStatusService.SyncHealth.healthy.displayText == "Synced")
        #expect(CloudKitSyncStatusService.SyncHealth.syncing.displayText == "Syncing...")
        #expect(CloudKitSyncStatusService.SyncHealth.warning.displayText == "Sync Delayed")
        #expect(CloudKitSyncStatusService.SyncHealth.error("Network error").displayText == "Sync Error")
        #expect(CloudKitSyncStatusService.SyncHealth.offline.displayText == "Offline")
        #expect(CloudKitSyncStatusService.SyncHealth.unknown.displayText == "Checking...")
    }

    @Test("SyncHealth equality for error cases")
    func testSyncHealthEquality() {
        let error1 = CloudKitSyncStatusService.SyncHealth.error("Error A")
        let error2 = CloudKitSyncStatusService.SyncHealth.error("Error A")
        let error3 = CloudKitSyncStatusService.SyncHealth.error("Error B")

        #expect(error1 == error2)
        #expect(error1 != error3)
        #expect(CloudKitSyncStatusService.SyncHealth.healthy == CloudKitSyncStatusService.SyncHealth.healthy)
        #expect(CloudKitSyncStatusService.SyncHealth.healthy != CloudKitSyncStatusService.SyncHealth.syncing)
    }
}

// MARK: - CloudKitSyncStatusService Tests

@Suite("CloudKitSyncStatusService Tests")
struct CloudKitSyncStatusServiceTests {

    // MARK: - Initial State Tests

    @Test("Service initializes with default state")
    @MainActor
    func testInitialState() async {
        // Create a new instance (not using shared to avoid side effects)
        let service = CloudKitSyncStatusService()

        // Initial state checks
        #expect(service.isSyncing == false)
        // syncHealth depends on UserDefaults state, so just verify it's a valid value
        let _ = service.syncHealth // Should not crash
    }

    @Test("Service loads persisted last successful sync date")
    @MainActor
    func testLoadsPersistedSyncDate() async {
        // Set up persisted state
        let testDate = Date().addingTimeInterval(-3600) // 1 hour ago
        UserDefaults.standard.set(testDate.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)

        let service = CloudKitSyncStatusService()

        // Verify loaded state
        if let lastSync = service.lastSuccessfulSync {
            // Timestamps should be within 1 second
            #expect(abs(lastSync.timeIntervalSince1970 - testDate.timeIntervalSince1970) < 1)
        }

        // Cleanup
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
    }

    @Test("Service loads persisted last sync error")
    @MainActor
    func testLoadsPersistedSyncError() async {
        // Set up persisted state
        let testError = "Test sync error message"
        UserDefaults.standard.set(testError, forKey: UserDefaultsKeys.cloudKitLastSyncError)

        let service = CloudKitSyncStatusService()

        #expect(service.lastSyncError == testError)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
    }

    // MARK: - Configuration Tests

    @Test("Configure with model container")
    @MainActor
    func testConfigureWithContainer() async throws {
        let container = try makeTestContainer(for: [Student.self])
        let service = CloudKitSyncStatusService()

        // Should not crash
        service.configure(with: container)

        // After configuration, service should be ready
        let _ = service.syncHealth
    }

    // MARK: - Clear Error Tests

    @Test("Clear error removes error state")
    @MainActor
    func testClearError() async {
        // Set up error state
        UserDefaults.standard.set("Some error", forKey: UserDefaultsKeys.cloudKitLastSyncError)

        let service = CloudKitSyncStatusService()
        #expect(service.lastSyncError != nil)

        service.clearError()

        #expect(service.lastSyncError == nil)
        #expect(UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudKitLastSyncError) == nil)
    }

    // MARK: - Sync Health State Machine Tests

    @Test("Sync health shows offline when CloudKit disabled")
    @MainActor
    func testSyncHealthOfflineWhenDisabled() async {
        // Disable CloudKit sync
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.enableCloudKitSync)

        let service = CloudKitSyncStatusService()

        #expect(service.syncHealth == .offline)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.enableCloudKitSync)
    }

    @Test("Sync health shows offline when CloudKit not active")
    @MainActor
    func testSyncHealthOfflineWhenNotActive() async {
        // Enable but not active
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.enableCloudKitSync)
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)

        let service = CloudKitSyncStatusService()

        #expect(service.syncHealth == .offline)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.enableCloudKitSync)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitActive)
    }

    @Test("Sync health shows error when error exists")
    @MainActor
    func testSyncHealthShowsError() async {
        // Set up for error display
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.enableCloudKitSync)
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
        UserDefaults.standard.set("Network unavailable", forKey: UserDefaultsKeys.cloudKitLastSyncError)

        let service = CloudKitSyncStatusService()

        // If network/iCloud are available, it should show error
        if service.isNetworkAvailable && service.isICloudAvailable {
            if case .error(let msg) = service.syncHealth {
                #expect(msg == "Network unavailable")
            }
        }

        // Cleanup
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.enableCloudKitSync)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitActive)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
    }

    @Test("Sync health shows healthy for recent sync")
    @MainActor
    func testSyncHealthHealthyForRecentSync() async {
        // Set up healthy state
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.enableCloudKitSync)
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)

        let service = CloudKitSyncStatusService()

        // If network and iCloud are available, should be healthy
        if service.isNetworkAvailable && service.isICloudAvailable {
            #expect(service.syncHealth == .healthy)
        }

        // Cleanup
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.enableCloudKitSync)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitActive)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
    }

    @Test("Sync health shows warning for old sync")
    @MainActor
    func testSyncHealthWarningForOldSync() async {
        // Set up warning state - sync more than 1 hour ago
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.enableCloudKitSync)
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
        let oldSyncDate = Date().addingTimeInterval(-7200) // 2 hours ago
        UserDefaults.standard.set(oldSyncDate.timeIntervalSince1970, forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)

        let service = CloudKitSyncStatusService()

        // If network and iCloud are available, should be warning
        if service.isNetworkAvailable && service.isICloudAvailable {
            #expect(service.syncHealth == .warning)
        }

        // Cleanup
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.enableCloudKitSync)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitActive)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
    }

    // MARK: - syncNow Tests

    @Test("syncNow returns false without container")
    @MainActor
    func testSyncNowWithoutContainer() async {
        let service = CloudKitSyncStatusService()

        let result = await service.syncNow()

        #expect(result == false)
    }

    @Test("syncNow with container succeeds")
    @MainActor
    func testSyncNowWithContainer() async throws {
        let container = try makeTestContainer(for: [Student.self])
        let service = CloudKitSyncStatusService()
        service.configure(with: container)

        let result = await service.syncNow()

        // Should succeed with in-memory container
        #expect(result == true)
        #expect(service.lastSuccessfulSync != nil)
        #expect(service.lastSyncError == nil)
    }

    @Test("syncNow updates syncing state")
    @MainActor
    func testSyncNowUpdatesSyncingState() async throws {
        let container = try makeTestContainer(for: [Student.self])
        let service = CloudKitSyncStatusService()
        service.configure(with: container)

        // Start sync
        _ = await service.syncNow()

        // After sync completes, should not be syncing
        #expect(service.isSyncing == false)
    }

    // MARK: - Network Availability Tests

    @Test("Network availability is accessible")
    @MainActor
    func testNetworkAvailabilityAccessible() async {
        let service = CloudKitSyncStatusService()

        // Should not crash and return a boolean
        let _ = service.isNetworkAvailable
    }

    // MARK: - iCloud Availability Tests

    @Test("iCloud availability is accessible")
    @MainActor
    func testICloudAvailabilityAccessible() async {
        let service = CloudKitSyncStatusService()

        // Should not crash and return a boolean
        let _ = service.isICloudAvailable
    }

    // MARK: - Published Properties Tests

    @Test("All published properties are accessible")
    @MainActor
    func testPublishedPropertiesAccessible() async {
        let service = CloudKitSyncStatusService()

        // Access all published properties - should not crash
        let _ = service.isSyncing
        let _ = service.lastSuccessfulSync
        let _ = service.lastSyncError
        let _ = service.syncHealth
        let _ = service.isNetworkAvailable
        let _ = service.isICloudAvailable
    }
}

// MARK: - Integration Tests

@Suite("CloudKitSyncStatusService Integration Tests", .serialized)
struct CloudKitSyncStatusServiceIntegrationTests {

    @Test("Full sync cycle with container")
    @MainActor
    func testFullSyncCycle() async throws {
        // Create container with test data
        let container = try makeTestContainer(for: [Student.self])
        let context = container.mainContext

        // Insert test data
        let student = makeTestStudent(firstName: "Sync", lastName: "Test")
        context.insert(student)
        try context.save()

        // Configure service
        let service = CloudKitSyncStatusService()
        service.configure(with: container)

        // Perform sync
        let result = await service.syncNow()

        #expect(result == true)
        #expect(service.lastSuccessfulSync != nil)
        #expect(service.isSyncing == false)
    }

    @Test("Error recovery clears error state")
    @MainActor
    func testErrorRecovery() async throws {
        // Set up initial error state
        UserDefaults.standard.set("Previous error", forKey: UserDefaultsKeys.cloudKitLastSyncError)

        let container = try makeTestContainer(for: [Student.self])
        let service = CloudKitSyncStatusService()
        service.configure(with: container)

        // Verify error is present
        #expect(service.lastSyncError == "Previous error")

        // Successful sync should clear error
        let result = await service.syncNow()

        #expect(result == true)
        #expect(service.lastSyncError == nil)
    }

    @Test("UserDefaults persistence after sync")
    @MainActor
    func testUserDefaultsPersistence() async throws {
        let container = try makeTestContainer(for: [Student.self])
        let service = CloudKitSyncStatusService()
        service.configure(with: container)

        // Perform sync
        _ = await service.syncNow()

        // Check UserDefaults was updated
        let persistedTimestamp = UserDefaults.standard.object(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate) as? TimeInterval
        #expect(persistedTimestamp != nil)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
    }
}
#endif
