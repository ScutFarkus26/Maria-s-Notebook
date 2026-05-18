import Foundation
import CoreData
import CloudKit
import OSLog

extension ClassroomSharingService {

    private static let autoCreateLogger = Logger.app(category: "ClassroomSharing")

    /// Best-effort on-launch flow that guarantees a CKShare exists for the
    /// shared store whenever the user has shared-store data to sync.
    ///
    /// Without an active CKShare, every record in the shared-store config
    /// (`databaseScope = .shared`) is an orphan from CloudKit's perspective
    /// and triggers `NSCocoaErrorDomain 134060` —
    /// `NSCloudKitMirroringDelegate` then aborts every subsequent
    /// import/export for the rest of the process. Creating the share here
    /// (instead of waiting for the user to open
    /// Settings → Classroom Sharing) lets the lead guide's data sync from
    /// first launch.
    ///
    /// Flow:
    ///   1. Run `SharedStoreZoneRepair` so `hasActiveShare` reflects
    ///      current CloudKit state (cheap; no-op when there are no
    ///      orphans).
    ///   2. If a share already exists → return.
    ///   3. If the user is already an assistant (accepted someone else's
    ///      share) → return. We must never auto-create a competing share
    ///      on an assistant device.
    ///   4. Pick a seed record from the shared store. If the shared store
    ///      is empty (fresh install on the lead device) → return; the
    ///      `SharedStoreOrphanGuard` save observer will re-invoke this
    ///      flow once the first shared-store record is created.
    ///   5. Call `container.share([seed], to: nil)` to create the share.
    ///   6. Create the local lead-guide `CDClassroomMembership` pointing
    ///      at the new zone, if one doesn't already exist.
    ///   7. Re-run `SharedStoreZoneRepair` so the already-orphaned
    ///      records get attached to the new share.
    ///
    /// All errors are caught and logged — the user can keep working
    /// offline, and the next launch (or the next save) will retry.
    static func ensureShareExistsOnLaunch(coreDataStack: CoreDataStack) async {
        guard coreDataStack.isCloudKitActive else { return }
        guard let store = coreDataStack.sharedPersistentStore else { return }

        let container = coreDataStack.container

        // Step 1: refresh hasActiveShare from CloudKit.
        await SharedStoreZoneRepair.shared.run(coreDataStack: coreDataStack)
        if SharedStoreZoneRepair.shared.hasActiveShare { return }

        // Defensive double-check via the container directly — if CloudKit
        // returned a share through any other path, don't try to create a
        // second one.
        if (try? container.fetchShares(in: store).first) != nil {
            return
        }

        // Step 3: skip auto-create on devices that have accepted an
        // external share. The assistant role is created in
        // `acceptShare(metadata:)` and persists across launches.
        let context = coreDataStack.viewContext
        let repo = ClassroomRepository(context: context)
        if let membership = repo.fetchCurrentMembership(), membership.role == .assistant {
            return
        }

        // Step 4: find a seed record from the shared store.
        guard let seed = pickSeedRecord(coreDataStack: coreDataStack, store: store) else {
            autoCreateLogger.info("Auto-create CKShare skipped — shared store has no records yet")
            return
        }

        // Step 5: create the share. We pass `to: nil` so the framework
        // creates a new CKShare + custom zone for us. The share's title
        // and participant list are left to the existing
        // Settings → Classroom Sharing flow to populate via
        // UICloudSharingController.
        let newShare: CKShare
        do {
            let result = try await container.share([seed], to: nil)
            newShare = result.1
            autoCreateLogger.info("Auto-created classroom CKShare in zone \(newShare.recordID.zoneID.zoneName, privacy: .public)")
        } catch {
            autoCreateLogger.error("Auto-create CKShare failed — will retry on next launch: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Step 6: create the local lead-guide membership if missing.
        if repo.fetchCurrentMembership() == nil {
            repo.createMembership(
                classroomZoneID: newShare.recordID.zoneID.zoneName,
                role: .leadGuide,
                ownerIdentity: newShare.owner.userIdentity.userRecordID?.recordName ?? "self"
            )
            _ = repo.save(reason: "Auto-create classroom membership")
        }

        // Step 7: sweep the pre-existing orphans into the new share.
        // `runIfNeeded` is idempotent and refreshes `hasActiveShare`.
        await SharedStoreZoneRepair.shared.run(coreDataStack: coreDataStack)
    }

    /// Picks a deterministic seed record from the shared store to
    /// initialise the CKShare zone with. Prefers an existing lead-guide
    /// `CDClassroomMembership` so the share's first record is something
    /// the assistant will immediately see meaningful state for. Falls
    /// back to any orphaned shared-store record so cold installs with
    /// only seeded curriculum still produce a share.
    private static func pickSeedRecord(
        coreDataStack: CoreDataStack,
        store: NSPersistentStore
    ) -> NSManagedObject? {
        let context = coreDataStack.viewContext

        // First choice: an existing CDClassroomMembership for the lead.
        let repo = ClassroomRepository(context: context)
        if let membership = repo.fetchCurrentMembership(), membership.role == .leadGuide {
            return membership
        }

        // Second choice: any record in the shared store. Iterate the
        // entity list in a stable, intentional order so test seeds and
        // production curriculum produce the same seed across launches.
        let preferredOrder = [
            "Lesson", "Student", "Procedure", "Schedule",
            "Track", "SequenceTrack", "Resource", "Story"
        ]
        let entityNames = preferredOrder + CoreDataStack.sharedEntityNames
            .subtracting(preferredOrder)
            .sorted()

        for name in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.affectedStores = [store]
            request.fetchLimit = 1
            if let record = try? context.fetch(request).first {
                return record
            }
        }

        return nil
    }
}
