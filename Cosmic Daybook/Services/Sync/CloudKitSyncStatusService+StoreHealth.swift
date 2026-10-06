import CoreData
import Foundation
import OSLog

// MARK: - Per-store health

extension CloudKitSyncStatusService {

    /// Which store an `NSPersistentCloudKitContainer` event belongs to.
    func syncedStore(forIdentifier identifier: String?) -> SyncedStore {
        if let syncedStoreResolver { return syncedStoreResolver(identifier) }
        return SyncedStore(
            identifier: identifier,
            notebookIdentifier: coreDataStack?.privatePersistentStore?.identifier,
            classroomShareIdentifier: coreDataStack?.sharedPersistentStore?.identifier
        )
    }

    static func eventTypeName(_ type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup: return "Setup"
        case .import: return "Import"
        case .export: return "Export"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - The stopped flag

    /// Whether a failed event means the store's mirroring delegate is dead:
    ///   1. A setup failure: the delegate threw while starting. Not one for
    ///      want of an iCloud account (134400) or a network, which is account
    ///      or connection state and runs again once that's back (TN3164).
    ///   2. NSCocoaErrorDomain 134421: "Export encountered an unhandled
    ///      exception while analyzing history in the store".
    ///   3. NSCocoaErrorDomain 134406: a request "was aborted because the
    ///      mirroring delegate never successfully initialized", the shape seen
    ///      when the store becomes unreadable mid-session (another process
    ///      migrated it underneath us).
    ///   4. The message says "never successfully initialized" (belt and
    ///      braces), matched case-insensitively: Core Data spells it
    ///      lower-case inside 134406's description.
    static func marksMirroringDead(type: NSPersistentCloudKitContainer.EventType, error: any Error) -> Bool {
        let nsError = error as NSError
        if type == .setup { return !CloudKitStoreHealth.isAccountOrNetworkFailure(error) }
        if nsError.domain == NSCocoaErrorDomain, nsError.code == 134_421 || nsError.code == 134_406 { return true }
        let description = nsError.localizedDescription
        return description.range(of: "never successfully initialized", options: .caseInsensitive) != nil
    }

    /// `store`'s mirroring delegate died: sets `mirroringDelegateFailed` until
    /// that store next imports or exports successfully.
    func markMirroringStopped(by store: SyncedStore) {
        stoppedStores.insert(store)
        if !mirroringDelegateFailed { mirroringDelegateFailed = true }
        Self.logger.error("CloudKit mirroring delegate marked as failed: \(store.displayName, privacy: .public)")
    }

    /// `store` imported or exported successfully, so its delegate works: it
    /// no longer holds the stopped flag, which clears once no store does. A
    /// setup event alone never clears it (Apple documents no such recovery).
    func clearMirroringStopped(by store: SyncedStore) {
        guard stoppedStores.remove(store) != nil, stoppedStores.isEmpty, mirroringDelegateFailed else { return }
        mirroringDelegateFailed = false
        Self.logger.notice("CloudKit sync is running again: \(store.displayName, privacy: .public) synced")
        SyncEventLogger.shared.log("cloudkit", status: "success", message: "iCloud sync is running again")
    }

    // MARK: - Another Apple Account

    /// Another Apple Account signed in while the app runs. What this service
    /// knew (when it last synced, which stores failed, the stopped flag, the
    /// shown error, the waiting count) was the old account's.
    func resetForNewAccount() {
        Self.logger.notice("The iCloud account changed: sync status starts over for the new account")
        syncDatePersistTask?.cancel()
        syncDatePersistTask = nil
        unpersistedSyncDate = nil
        syncDatePersistedAt = nil
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSuccessfulSyncDate)
        // The old account's imports and exports say nothing about the new
        // one's download: dedup ties and orphan graces would count them, and
        // the purge would trust its export dates.
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSuccessfulImportStartByStore)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastSuccessfulExportStartByStore)
        lastSuccessfulSync = nil
        storeHealth = CloudKitStoreHealth()
        mirroringDelegateFailed = false
        if pendingSyncCount != 0 { pendingSyncCount = 0 }
        clearError()
    }
}
