import Foundation
import CoreData
import OSLog

// MARK: - Observer Setup

extension CloudKitSyncStatusService {

    /// Remote changes and local saves. CloudKit's events have their own
    /// stream (`startCloudKitEventStream`), and store changes start 2 s later
    /// (`startObservingStoreChanges`).
    func startObserving() {
        guard let monitoredCoordinator = monitoredPersistentStoreCoordinator else {
            Self.logger.warning("Cannot observe CloudKit status before a Core Data stack is configured")
            return
        }

        let center = NotificationCenter.default

        // Remote changes arrive as iOS 27 typed messages, read by one
        // main-actor task. A remote change is posted for every write to the
        // store, this device's own saves included, so it only feeds the
        // first-download overlay; it says nothing about iCloud. The stream is
        // made here, not inside the task, so nothing posted before the task
        // first runs is missed.
        let remoteChanges = center.messages(of: monitoredCoordinator, for: .remoteChange, bufferSize: 256)
        messageObservationTasks.append(Task { [weak self] in
            for await _ in remoteChanges {
                self?.scheduleRemoteChangeHandling()
            }
        })

        // Local saves (outgoing sync trigger) stay on the classic notification:
        // this watches every context on the coordinator, and on the iOS/macOS
        // 27.0 SDK the object-ID save messages arrive twice per save (and the
        // async variant never for main-queue contexts), while `DidSaveMessage`
        // covers main-queue contexts only.
        saveObserver = center.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Context-save notifications identify their source context. Filter
            // on the posting context's queue before hopping to MainActor so a
            // local-only Sample Class save cannot look like a CloudKit export.
            guard let context = notification.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === monitoredCoordinator else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingSaveTask?.cancel()
                self.pendingSaveTask = Task { [weak self] in
                    self?.handleLocalSave()
                }
            }
        }
    }

    /// Store coordinator changes (CloudKit delegate teardowns): stores added
    /// or removed during migrations or configuration changes.
    func startObservingStoreChanges() {
        guard let monitoredCoordinator = monitoredPersistentStoreCoordinator else { return }
        let storeChanges = NotificationCenter.default.messages(
            of: monitoredCoordinator, for: .storesDidChangeAsync, bufferSize: 256
        )
        messageObservationTasks.append(Task { [weak self] in
            for await _ in storeChanges {
                guard let self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingStoreChangeTask?.cancel()
                self.pendingStoreChangeTask = Task { [weak self] in
                    self?.handleStoreCoordinatorChange()
                }
            }
        })
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

        messageObservationTasks.forEach { $0.cancel() }
        messageObservationTasks = []
        if let observer = saveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        saveObserver = nil
    }

    func stopObserving() {
        Task { [weak self] in
            self?.removeAllObservers()
            self?.cloudKitEventTask?.cancel()
            self?.cloudKitEventTask = nil
        }
    }
}
