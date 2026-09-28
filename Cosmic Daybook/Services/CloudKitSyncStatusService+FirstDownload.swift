import Foundation
import CoreData
import OSLog

// MARK: - First download

extension CloudKitSyncStatusService {

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
