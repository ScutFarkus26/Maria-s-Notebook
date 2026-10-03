import CoreData
import Foundation

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
}
