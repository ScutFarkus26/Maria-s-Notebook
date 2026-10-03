import Foundation
import CoreData
import OSLog

// MARK: - First download

extension CloudKitSyncStatusService {

    /// While the gate is armed, listens for the private store's first import
    /// from the moment the stack is configured. The full observers start
    /// 2 s later (see `configure`), and an import that finished inside that
    /// window was missed, leaving the gate armed until some later import.
    /// Ends once the gate opens; `removeAllObservers` cancels it with the rest.
    func watchForFirstDownloadIfPending() {
        guard FirstDownloadGate.isPending() else { return }
        let events = NotificationCenter.default.messages(
            of: NSPersistentCloudKitContainer.self, for: .eventChanged, bufferSize: 256
        )
        messageObservationTasks.append(Task { [weak self] in
            for await message in events {
                let event = message.event
                guard event.type == .import, event.endDate != nil, event.succeeded else { continue }
                guard let self else { return }
                self.finishFirstDownloadIfNeeded(importedStoreIdentifier: event.storeIdentifier)
                if !FirstDownloadGate.isPending() { return }
            }
        })
    }

    /// Opens `FirstDownloadGate` once an import into the private store has
    /// finished successfully, then runs what the gate held back: the built-in
    /// template seed (a no-op when the notebook's own came down) and the
    /// classroom records this device created while it waited for the pin.
    /// The shared store's import says nothing about the private store's, so
    /// it never opens the gate.
    func finishFirstDownloadIfNeeded(importedStoreIdentifier: String?) {
        guard let stack = coreDataStack,
              let privateStore = stack.privatePersistentStore,
              importedStoreIdentifier == privateStore.identifier,
              FirstDownloadGate.open() else { return }
        Self.logger.notice("First download from iCloud finished: template seeding and classroom attach resume")
        let context = stack.viewContext
        BuiltInTemplateSeeder.seedIfNeeded(context: context)
        if context.hasChanges {
            context.safeSave()
        }
        SharedStoreOrphanGuard.shared.flushPendingIfPossible()
    }
}
