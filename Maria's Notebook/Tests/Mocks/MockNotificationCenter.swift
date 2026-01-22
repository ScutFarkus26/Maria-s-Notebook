// MockNotificationCenter.swift
// Mock implementation for NotificationCenter to test notification handling

#if canImport(Testing)
import Foundation
@testable import Maria_s_Notebook

/// Mock notification center for testing notification-based logic
@MainActor
final class MockNotificationCenter {
    /// Recorded notifications that were posted
    private(set) var postedNotifications: [(name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]?)] = []

    /// Registered observers
    private var observers: [(name: Notification.Name, handler: (Notification) -> Void)] = []

    /// Post a notification
    func post(name: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        postedNotifications.append((name: name, object: object, userInfo: userInfo))

        // Notify observers
        let notification = Notification(name: name, object: object, userInfo: userInfo)
        for observer in observers where observer.name == name {
            observer.handler(notification)
        }
    }

    /// Add an observer for a specific notification
    func addObserver(forName name: Notification.Name, handler: @escaping (Notification) -> Void) {
        observers.append((name: name, handler: handler))
    }

    /// Remove all observers
    func removeAllObservers() {
        observers.removeAll()
    }

    /// Check if a notification was posted
    func wasNotificationPosted(_ name: Notification.Name) -> Bool {
        postedNotifications.contains { $0.name == name }
    }

    /// Get count of notifications with a specific name
    func notificationCount(for name: Notification.Name) -> Int {
        postedNotifications.filter { $0.name == name }.count
    }

    /// Clear all recorded notifications
    func clearRecordedNotifications() {
        postedNotifications.removeAll()
    }
}

/// Extension to provide common CloudKit-related notification names for testing
extension Notification.Name {
    /// Test helper: Simulates NSPersistentStoreRemoteChange notification
    static let testRemoteChange = Notification.Name("TestRemoteChangeNotification")

    /// Test helper: Simulates NSManagedObjectContextDidSave notification
    static let testLocalSave = Notification.Name("TestLocalSaveNotification")

    /// Test helper: Simulates NSUbiquityIdentityDidChange notification
    static let testICloudAccountChange = Notification.Name("TestICloudAccountChangeNotification")
}

/// Helper class to track notification observer lifecycle
final class NotificationObserverTracker {
    private(set) var addedObservers: [Notification.Name] = []
    private(set) var removedObservers: [Notification.Name] = []

    func recordAddObserver(for name: Notification.Name) {
        addedObservers.append(name)
    }

    func recordRemoveObserver(for name: Notification.Name) {
        removedObservers.append(name)
    }

    var hasLeakedObservers: Bool {
        addedObservers.count != removedObservers.count
    }

    func reset() {
        addedObservers.removeAll()
        removedObservers.removeAll()
    }
}
#endif
