import Foundation
import CoreData
import CloudKit
import OSLog

// MARK: - Orphan Detection
//
// An "orphan" is a classroom record sitting in the private store that belongs
// to no CKShare zone. CloudKit cannot export it, and one of them poisons the
// mirroring delegate for every subsequent import and export.

extension SharedStoreZoneRepair {

    /// Everything one repair pass reads from: which entities count as
    /// classroom data, and the store, context, and container to read them out
    /// of. Bundled so detection and repair cannot drift onto different stores.
    struct RepairScope {
        let entityNames: [String]
        let store: NSPersistentStore
        let context: NSManagedObjectContext
        let container: NSPersistentCloudKitContainer
    }

    /// Fetches every classroom record in the private store and partitions out
    /// the ones that belong to no CKShare zone.
    func collectOrphans(in scope: RepairScope) -> (orphans: [NSManagedObject], byEntity: [String: Int]) {
        var allObjectIDs: [NSManagedObjectID] = []
        var objectsByID: [NSManagedObjectID: NSManagedObject] = [:]
        var entityByID: [NSManagedObjectID: String] = [:]

        for entityName in scope.entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.affectedStores = [scope.store]
            request.returnsObjectsAsFaults = true
            do {
                let objects = try scope.context.fetch(request)
                for obj in objects {
                    allObjectIDs.append(obj.objectID)
                    objectsByID[obj.objectID] = obj
                    entityByID[obj.objectID] = entityName
                }
            } catch {
                let detail = error.localizedDescription
                let warnMsg = "Failed to fetch \(entityName) for zone check: \(detail)"
                Self.logger.warning("\(warnMsg, privacy: .public)")
            }
        }

        guard !allObjectIDs.isEmpty else { return ([], [:]) }

        let inShare: [NSManagedObjectID: CKShare]
        do {
            inShare = try scope.container.fetchShares(matching: allObjectIDs)
        } catch {
            Self.logger.error("fetchShares(matching:) failed: \(error.localizedDescription, privacy: .public)")
            return ([], [:])
        }

        var orphans: [NSManagedObject] = []
        var byEntity: [String: Int] = [:]
        for id in allObjectIDs where inShare[id] == nil {
            if let obj = objectsByID[id] {
                orphans.append(obj)
                let name = entityByID[id] ?? "Unknown"
                byEntity[name, default: 0] += 1
            }
        }
        return (orphans, byEntity)
    }
}
