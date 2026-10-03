import Foundation
import CoreData
import OSLog

// MARK: - Observer Setup

extension CloudKitSyncStatusService {

    // swiftlint:disable:next function_body_length
    func startObserving() {
        guard let monitoredCoordinator = monitoredPersistentStoreCoordinator else {
            Self.logger.warning("Cannot observe CloudKit status before a Core Data stack is configured")
            return
        }

        let center = NotificationCenter.default

        // Remote changes (incoming CloudKit sync), store changes and CloudKit
        // events arrive as iOS 27 typed messages. Each stream is read by one
        // main-actor task, so a started/finished event pair is handled in the
        // order CloudKit posted it. The buffer is generous because a dropped
        // "finished" event would leave the syncing indicator on. The streams
        // are made here, not inside the tasks, so nothing posted before a
        // task first runs is missed.
        let remoteChanges = center.messages(of: monitoredCoordinator, for: .remoteChange, bufferSize: 256)
        let storeChanges = center.messages(of: monitoredCoordinator, for: .storesDidChangeAsync, bufferSize: 256)
        let cloudKitEvents = center.messages(
            of: NSPersistentCloudKitContainer.self, for: .eventChanged, bufferSize: 256
        )

        messageObservationTasks.append(Task { [weak self] in
            for await _ in remoteChanges {
                self?.scheduleRemoteChangeHandling()
            }
        })

        // Store coordinator changes (CloudKit delegate teardowns): stores
        // added or removed during migrations or configuration changes.
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

        // CloudKit sync events (setup, import, export): the exact event type
        // and whether it succeeded, which is more precise than inferring sync
        // state from saves and remote changes alone.
        messageObservationTasks.append(Task { [weak self] in
            for await message in cloudKitEvents {
                let event = message.event
                self?.handleCloudKitEvent(
                    type: event.type, isFinished: event.endDate != nil,
                    succeeded: event.succeeded,
                    error: event.error,
                    startDate: event.startDate,
                    storeIdentifier: event.storeIdentifier
                )
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
        }
    }
}
