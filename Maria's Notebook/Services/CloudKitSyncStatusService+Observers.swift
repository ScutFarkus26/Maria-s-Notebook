import Foundation
import CoreData

// MARK: - Observer Setup

extension CloudKitSyncStatusService {

    // swiftlint:disable:next function_body_length
    func startObserving() {
        // Observe remote changes (incoming CloudKit sync)
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingRemoteChangeTask?.cancel()
                self.pendingRemoteChangeTask = Task { @MainActor [weak self] in
                    self?.handleRemoteChange()
                }
            }
        }

        // Observe local saves (outgoing sync trigger)
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingSaveTask?.cancel()
                self.pendingSaveTask = Task { @MainActor [weak self] in
                    self?.handleLocalSave()
                }
            }
        }

        // Observe store coordinator changes (CloudKit delegate teardowns)
        // This notification fires when stores are added/removed from the coordinator
        // which can happen during migrations or configuration changes
        storeCoordinatorChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreCoordinatorStoresDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingStoreChangeTask?.cancel()
                self.pendingStoreChangeTask = Task { @MainActor [weak self] in
                    self?.handleStoreCoordinatorChange()
                }
            }
        }

        // Observe CloudKit sync events (setup, import, export) for precise status tracking.
        // This is Apple's recommended notification (iOS 14+/macOS 11+) for monitoring
        // NSPersistentCloudKitContainer sync operations. It provides the exact event type
        // and whether it succeeded or failed, which is more precise than inferring sync
        // state from NSManagedObjectContextDidSave + NSPersistentStoreRemoteChange alone.
        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract event data before crossing isolation boundary (Notification is not Sendable)
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let type = event.type
            let isFinished = event.endDate != nil
            let succeeded = event.succeeded
            let errorDesc = event.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleCloudKitEvent(
                    type: type, isFinished: isFinished,
                    succeeded: succeeded,
                    errorDescription: errorDesc
                )
            }
        }
    }

    /// Removes all notification observers and cancels pending tasks.
    /// Safe to call multiple times. Must be called on @MainActor.
    func removeAllObservers() {
        // Cancel all pending tasks
        pendingRemoteChangeTask?.cancel()
        pendingRemoteChangeTask = nil
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        pendingStoreChangeTask?.cancel()
        pendingStoreChangeTask = nil

        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = saveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = storeCoordinatorChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = cloudKitEventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        remoteChangeObserver = nil
        saveObserver = nil
        storeCoordinatorChangeObserver = nil
        cloudKitEventObserver = nil
    }

    nonisolated func stopObserving() {
        Task { @MainActor [weak self] in
            self?.removeAllObservers()
        }
    }
}
