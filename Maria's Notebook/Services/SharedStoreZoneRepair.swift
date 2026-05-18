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
///
/// When a CKShare does exist, the service attaches every detected
/// orphan to it. Re-runs are cheap when the shared store has no orphans
/// and are triggered from three places:
///   1. Post-launch migrations (after the final viewContext save)
///   2. ClassroomSharingService when `isSharing` transitions `false → true`
///   3. DeduplicationCoordinator after each post-import dedup pass
@Observable
@MainActor
final class SharedStoreZoneRepair {

    static let shared = SharedStoreZoneRepair()

    private static let logger = Logger.app(category: "SharedStoreZoneRepair")

    // MARK: - Observable State

    private(set) var orphanCount: Int = 0
    private(set) var orphansByEntity: [String: Int] = [:]
    private(set) var lastUnrecoverableOrphans: [NSManagedObjectID] = []
    private(set) var lastRunAt: Date?
    private(set) var repairInProgress: Bool = false
    private(set) var hasActiveShare: Bool = false

    private init() {}

    // MARK: - Public API

    /// Runs the detection-and-repair pass on the shared singleton.
    /// Idempotent and cheap when the shared store has no orphans.
    static func runIfNeeded(coreDataStack: CoreDataStack) async {
        await shared.run(coreDataStack: coreDataStack)
    }

    /// Instance variant of `runIfNeeded`. Use the static form from call
    /// sites that don't need to bind to the singleton directly.
    func run(coreDataStack: CoreDataStack) async {
        guard coreDataStack.isCloudKitActive else { return }
        guard let store = coreDataStack.sharedPersistentStore else { return }
        guard !repairInProgress else { return }

        repairInProgress = true
        defer {
            repairInProgress = false
            lastRunAt = Date()
        }

        let entityNames = CoreDataStack.sharedEntityNames.sorted()
        let context = coreDataStack.viewContext
        let container = coreDataStack.container

        let (orphans, perEntity) = collectOrphans(
            entityNames: entityNames,
            in: store,
            context: context,
            container: container
        )

        orphanCount = orphans.count
        orphansByEntity = perEntity

        guard !orphans.isEmpty else {
            lastUnrecoverableOrphans = []
            hasActiveShare = (try? container.fetchShares(in: store).first) != nil
            return
        }

        let existingShare: CKShare?
        do {
            existingShare = try container.fetchShares(in: store).first
        } catch {
            Self.logger.error("Cannot inspect shares in shared store: \(error.localizedDescription, privacy: .public)")
            return
        }

        hasActiveShare = (existingShare != nil)

        if let share = existingShare {
            let unrecoverable = await attachOrphans(orphans, to: share, container: container)
            lastUnrecoverableOrphans = unrecoverable

            // Refresh the orphan picture after the repair pass so the
            // observable state reflects what remains stuck.
            let (remaining, remainingByEntity) = collectOrphans(
                entityNames: entityNames,
                in: store,
                context: context,
                container: container
            )
            orphanCount = remaining.count
            orphansByEntity = remainingByEntity
        } else {
            lastUnrecoverableOrphans = []
            let count = orphans.count
            Self.logger.warning("Shared store has \(count, privacy: .public) record(s) outside any CKShare zone, but no CKShare exists yet. CloudKit export will fail until the lead guide runs Settings → Classroom Sharing → Share Classroom.")
        }
    }

    // MARK: - Detection

    private func collectOrphans(
        entityNames: [String],
        in store: NSPersistentStore,
        context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer
    ) -> (orphans: [NSManagedObject], byEntity: [String: Int]) {
        var allObjectIDs: [NSManagedObjectID] = []
        var objectsByID: [NSManagedObjectID: NSManagedObject] = [:]
        var entityByID: [NSManagedObjectID: String] = [:]

        for entityName in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.affectedStores = [store]
            request.returnsObjectsAsFaults = true
            do {
                let objects = try context.fetch(request)
                for obj in objects {
                    allObjectIDs.append(obj.objectID)
                    objectsByID[obj.objectID] = obj
                    entityByID[obj.objectID] = entityName
                }
            } catch {
                let detail = error.localizedDescription
                Self.logger.warning("Failed to fetch \(entityName, privacy: .public) for zone check: \(detail, privacy: .public)")
            }
        }

        guard !allObjectIDs.isEmpty else { return ([], [:]) }

        let inShare: [NSManagedObjectID: CKShare]
        do {
            inShare = try container.fetchShares(matching: allObjectIDs)
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

    // MARK: - Attachment

    /// Attaches orphans to the share. Tries the batch path first; on
    /// failure falls back to per-record attachment so a single bad
    /// record can't block healthy ones. Returns the IDs of records that
    /// could not be attached.
    private func attachOrphans(
        _ orphans: [NSManagedObject],
        to share: CKShare,
        container: NSPersistentCloudKitContainer
    ) async -> [NSManagedObjectID] {
        Self.logger.info("Attaching \(orphans.count, privacy: .public) orphan record(s) to existing classroom share")

        // Fast path: batch attach.
        do {
            _ = try await container.share(orphans, to: share)
            Self.logger.info("Orphan attachment succeeded (batch)")
            return []
        } catch {
            Self.logger.warning("Batch orphan attach failed: \(error.localizedDescription, privacy: .public). Falling back to per-record attach.")
        }

        // Slow path: per-record attach.
        var failures: [NSManagedObjectID] = []
        var successCount = 0
        for orphan in orphans {
            do {
                _ = try await container.share([orphan], to: share)
                successCount += 1
            } catch {
                failures.append(orphan.objectID)
                let uri = orphan.objectID.uriRepresentation().absoluteString
                let detail = error.localizedDescription
                Self.logger.error("Per-record attach failed for \(uri, privacy: .public): \(detail, privacy: .public)")
            }
        }

        Self.logger.info("Per-record attach: \(successCount, privacy: .public) succeeded, \(failures.count, privacy: .public) unrecoverable")
        return failures
    }
}
