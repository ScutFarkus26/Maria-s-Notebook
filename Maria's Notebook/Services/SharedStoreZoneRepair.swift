import Foundation
import CoreData
import CloudKit
import OSLog

/// Repairs records in the shared store that are not associated with any
/// CKShare zone. An orphan in the shared store cannot be exported to
/// CloudKit and poisons the mirroring delegate ("Failed to assign an
/// object to a record zone … must be assigned to a zone using
/// shareManagedObjects:toShare:completion:"), which then blocks every
/// subsequent import/export until the next launch.
///
/// Safe-by-default: when no CKShare exists in the shared store, this
/// service only logs the orphan count — it never auto-creates a share
/// or deletes user data.
enum SharedStoreZoneRepair {
    private static let logger = Logger.app(category: "SharedStoreZoneRepair")

    /// Runs the detection-and-repair pass. Idempotent and cheap when the
    /// shared store has no orphans.
    @MainActor
    static func runIfNeeded(coreDataStack: CoreDataStack) async {
        guard coreDataStack.isCloudKitActive else { return }
        guard let store = coreDataStack.sharedPersistentStore else { return }

        let entityNames = CoreDataStack.sharedEntityNames.sorted()
        let context = coreDataStack.viewContext
        let orphans = collectOrphans(entityNames: entityNames, in: store, context: context, container: coreDataStack.container)

        guard !orphans.isEmpty else { return }

        let existingShare: CKShare?
        do {
            existingShare = try coreDataStack.container.fetchShares(in: store).first
        } catch {
            logger.error("Cannot inspect shares in shared store: \(error.localizedDescription, privacy: .public)")
            return
        }

        if let share = existingShare {
            await attachOrphans(orphans, to: share, container: coreDataStack.container)
        } else {
            let count = orphans.count
            logger.warning("Shared store has \(count, privacy: .public) record(s) outside any CKShare zone, but no CKShare exists yet. CloudKit export will fail until the lead guide runs Settings → Classroom Sharing → Share Classroom.")
        }
    }

    private static func collectOrphans(
        entityNames: [String],
        in store: NSPersistentStore,
        context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer
    ) -> [NSManagedObject] {
        var allObjectIDs: [NSManagedObjectID] = []
        var objectsByID: [NSManagedObjectID: NSManagedObject] = [:]

        for entityName in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.affectedStores = [store]
            request.returnsObjectsAsFaults = true
            do {
                let objects = try context.fetch(request)
                for obj in objects {
                    allObjectIDs.append(obj.objectID)
                    objectsByID[obj.objectID] = obj
                }
            } catch {
                let detail = error.localizedDescription
                logger.warning("Failed to fetch \(entityName, privacy: .public) for zone check: \(detail, privacy: .public)")
            }
        }

        guard !allObjectIDs.isEmpty else { return [] }

        let inShare: [NSManagedObjectID: CKShare]
        do {
            inShare = try container.fetchShares(matching: allObjectIDs)
        } catch {
            logger.error("fetchShares(matching:) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }

        return allObjectIDs.compactMap { id in
            inShare[id] == nil ? objectsByID[id] : nil
        }
    }

    private static func attachOrphans(
        _ orphans: [NSManagedObject],
        to share: CKShare,
        container: NSPersistentCloudKitContainer
    ) async {
        logger.info("Attaching \(orphans.count, privacy: .public) orphan record(s) to existing classroom share")
        do {
            _ = try await container.share(orphans, to: share)
            logger.info("Orphan attachment succeeded")
        } catch {
            logger.error("Failed to attach orphans to share: \(error.localizedDescription, privacy: .public)")
        }
    }
}
