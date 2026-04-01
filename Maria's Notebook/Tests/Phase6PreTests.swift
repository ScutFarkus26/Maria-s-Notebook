import Foundation
import CoreData
#if canImport(Testing)
import Testing
#endif

#if canImport(Testing)
@available(macOS 14, iOS 17, *)
@Suite("Phase 6 Pre-Tests: Conflict Resolution & Offline Prerequisites")
@MainActor
final class Phase6PreTests {

    // MARK: - DeduplicationCoordinator

    @Test("DeduplicationCoordinator init — no crash")
    func dedupCoordinatorInit() {
        let coordinator = DeduplicationCoordinator.shared
        // Singleton should exist and be usable
        #expect(coordinator != nil)
    }

    @Test("requestDeduplication fires without crash even without container")
    func dedupRequestFires() async {
        let coordinator = DeduplicationCoordinator.shared
        // Should not crash when no container is set (guard returns early)
        coordinator.requestDeduplication()
        try? await Task.sleep(for: .milliseconds(100))
    }

    @Test("NSPersistentStoreRemoteChange notification — no crash")
    func remoteChangeNotification() async {
        // Post the notification with no object — should not crash
        NotificationCenter.default.post(
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )
        try? await Task.sleep(for: .milliseconds(100))
    }

    // MARK: - Store Descriptions

    @Test("Store descriptions have NSPersistentHistoryTrackingKey enabled")
    func historyTrackingEnabled() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        for desc in stack.container.persistentStoreDescriptions {
            let historyTracking = desc.options[NSPersistentHistoryTrackingKey] as? NSNumber
            #expect(historyTracking?.boolValue == true,
                    "Store '\(desc.configuration ?? "?")' should have history tracking enabled")
        }
    }

    @Test("Background context merge policy is mergeByPropertyObjectTrump")
    func backgroundContextMergePolicy() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let bgCtx = stack.newBackgroundContext()
        let policy = bgCtx.mergePolicy as? NSMergePolicy
        #expect(policy == NSMergePolicy.mergeByPropertyObjectTrump,
                "Background context should use mergeByPropertyObjectTrump")
    }

    // MARK: - Debounce

    @Test("Multiple rapid requestDeduplication calls debounce without crash")
    func dedupDebounce() async {
        let coordinator = DeduplicationCoordinator.shared
        // Fire 10 rapid calls — should coalesce, not crash
        for _ in 0..<10 {
            coordinator.requestDeduplication()
        }
        try? await Task.sleep(for: .milliseconds(200))
    }
}
#endif
