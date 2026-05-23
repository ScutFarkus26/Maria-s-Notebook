import Foundation
import CoreData
import CloudKit
import OSLog

extension ClassroomSharingService {

    private static let autoCreateLogger = Logger.app(category: "ClassroomSharing")

    /// Best-effort flow that guarantees a CKShare exists in the lead guide's
    /// private store whenever they have classroom data to sync.
    ///
    /// Without an active CKShare, every classroom record is an orphan from
    /// CloudKit's perspective and triggers `NSCocoaErrorDomain 134060` —
    /// `NSCloudKitMirroringDelegate` then aborts every subsequent
    /// import/export for the rest of the process. Creating the share lets
    /// the lead guide's data sync from first launch.
    ///
    /// The actual `container.share(_:to:)` call is dispatched off the
    /// MainActor via `SharedStoreZoneRepair.createShareOffMain` so the
    /// well-known 10-minute kernel-ulock wait — which fires when CloudKit
    /// is unhealthy — blocks a cooperative-pool worker rather than the
    /// MainActor's runloop. Gated by `SharedStoreZoneRepair.isCircuitBreakerOpen`
    /// so a recent timeout doesn't re-arm the same hang.
    ///
    /// All errors are caught and logged — the user can keep working offline,
    /// and the next launch (or the next save) will retry.
    static func ensureShareExistsOnLaunch(coreDataStack: CoreDataStack) async {
        guard coreDataStack.isCloudKitActive else { return }
        guard let store = coreDataStack.privatePersistentStore else { return }
        let container = coreDataStack.container

        // Cheap check: does a share already exist? If so, we're done.
        if (try? container.fetchShares(in: store).first) != nil { return }

        // Skip on assistant devices — they have an accepted share in the
        // shared store and must never own a private-store share.
        let context = coreDataStack.viewContext
        let repo = ClassroomRepository(context: context)
        if let membership = repo.fetchCurrentMembership(), membership.role == .assistant {
            return
        }

        // Honor the circuit breaker — a recent Share-Export timeout means
        // CloudKit is sick and another attempt here would block for up to
        // 10 minutes.
        if SharedStoreZoneRepair.isCircuitBreakerOpen {
            autoCreateLogger.info("ensureShareExistsOnLaunch: circuit breaker open, deferring auto-create")
            return
        }

        guard let seed = pickSeedRecord(coreDataStack: coreDataStack, store: store) else {
            autoCreateLogger.info("Auto-create CKShare skipped — private store has no classroom records yet")
            return
        }
        let seedID = seed.objectID

        let newShare: CKShare
        do {
            newShare = try await SharedStoreZoneRepair.createShareOffMain(
                seedID: seedID,
                container: container
            )
            autoCreateLogger.info("Auto-created classroom CKShare in zone \(newShare.recordID.zoneID.zoneName, privacy: .public)")
        } catch {
            autoCreateLogger.error("Auto-create CKShare failed — will retry on next launch: \(error.localizedDescription, privacy: .public)")
            return
        }

        if repo.fetchCurrentMembership() == nil {
            repo.createMembership(
                classroomZoneID: newShare.recordID.zoneID.zoneName,
                role: .leadGuide,
                ownerIdentity: newShare.owner.userIdentity.userRecordID?.recordName ?? "self"
            )
            _ = repo.save(reason: "Auto-create classroom membership")
        }
    }

    /// Picks a deterministic seed record from the lead guide's private store
    /// to initialise the CKShare zone with. Prefers an existing lead-guide
    /// `CDClassroomMembership` so the share's first record is something
    /// the assistant will immediately see meaningful state for. Falls
    /// back to any classroom record so cold installs with only seeded
    /// curriculum still produce a share.
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

        // Second choice: any classroom record in the lead guide's private
        // store. Iterate the entity list in a stable, intentional order so
        // test seeds and production curriculum produce the same seed across
        // launches.
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

    /// Returns a CKShare ready to hand to `UICloudSharingController` /
    /// `NSSharingServicePicker`, creating one on demand if the shared
    /// store doesn't yet have a share.
    ///
    /// Mirrors the launch-time `ensureShareExistsOnLaunch` flow but
    /// surfaces errors so the Settings → Classroom Sharing button can
    /// show a useful message instead of presenting an empty sheet
    /// (the symptom when `currentShare` is nil at sheet-present time).
    func prepareShareForPresentation(coreDataStack: CoreDataStack) async throws -> CKShare {
        do {
            if let existing = try fetchExistingShare() {
                Self.autoCreateLogger.info("prepareShareForPresentation: returning existing share in zone \(existing.recordID.zoneID.zoneName, privacy: .public)")
                return existing
            }
        } catch {
            Self.autoCreateLogger.error("prepareShareForPresentation: fetchExistingShare threw — \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }

        guard coreDataStack.isCloudKitActive else {
            Self.autoCreateLogger.error("prepareShareForPresentation: CloudKit is not active on this device")
            throw ClassroomShareError.cloudKitInactive
        }
        // Seed must come from the .private-scope private store; .shared is
        // for received shares only.
        guard let store = coreDataStack.privatePersistentStore else {
            Self.autoCreateLogger.error("prepareShareForPresentation: private persistent store is unavailable")
            throw ClassroomShareError.sharedStoreUnavailable
        }

        let repo = ClassroomRepository(context: coreDataStack.viewContext)
        if let membership = repo.fetchCurrentMembership(), membership.role == .assistant {
            Self.autoCreateLogger.error("prepareShareForPresentation: refusing to create share on assistant device")
            throw ClassroomShareError.assistantCannotCreateShare
        }

        guard let seed = Self.pickSeedRecord(coreDataStack: coreDataStack, store: store) else {
            Self.autoCreateLogger.error("prepareShareForPresentation: no seed record available in shared store")
            throw ClassroomShareError.noSeedRecordAvailable
        }

        let seedEntity = seed.entity.name ?? "unknown"
        let seedID = seed.objectID
        Self.autoCreateLogger.info("prepareShareForPresentation: calling container.share with seed entity=\(seedEntity, privacy: .public)")

        let newShare: CKShare
        do {
            // Dispatch the blocking ulock wait to a cooperative-pool worker
            // so the MainActor stays responsive while CloudKit's Share-Export
            // task resolves.
            newShare = try await SharedStoreZoneRepair.createShareOffMain(
                seedID: seedID,
                container: container
            )
            Self.autoCreateLogger.info("prepareShareForPresentation: container.share succeeded; new zone=\(newShare.recordID.zoneID.zoneName, privacy: .public)")
        } catch {
            let ns = error as NSError
            Self.autoCreateLogger.error("prepareShareForPresentation: container.share failed — domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) description=\(ns.localizedDescription, privacy: .public) userInfo=\(ns.userInfo, privacy: .public)")
            // If CloudKit timed out, trip the breaker so subsequent
            // observational checks bail rather than queuing another 10-minute
            // hang.
            if ns.domain == "NSCocoaErrorDomain" && ns.code == 134060 {
                SharedStoreZoneRepair.tripCircuitBreakerOnTimeout()
            }
            throw error
        }

        if repo.fetchCurrentMembership() == nil {
            repo.createMembership(
                classroomZoneID: newShare.recordID.zoneID.zoneName,
                role: .leadGuide,
                ownerIdentity: newShare.owner.userIdentity.userRecordID?.recordName ?? "self"
            )
            _ = repo.save(reason: "Create classroom share")
        }

        // Update observable state directly from the share we just created.
        // We deliberately don't re-fetch via fetchExistingShare here — that
        // can throw transiently (the share zone may not be queryable for a
        // brief window after creation) and would silently leave
        // `currentShare = nil`, presenting an empty sharing sheet.
        updateShareState(newShare)

        return newShare
    }
}

/// Errors thrown by `prepareShareForPresentation` when the lead-guide
/// can't create or open a classroom share.
enum ClassroomShareError: LocalizedError {
    case cloudKitInactive
    case sharedStoreUnavailable
    case assistantCannotCreateShare
    case noSeedRecordAvailable

    var errorDescription: String? {
        switch self {
        case .cloudKitInactive:
            return "iCloud sync isn't active. Turn on iCloud for Maria's Notebook in System Settings and try again."
        case .sharedStoreUnavailable:
            return "Shared classroom storage isn't available on this device."
        case .assistantCannotCreateShare:
            return "Only the lead guide can share the classroom."
        case .noSeedRecordAvailable:
            return "Add a student, lesson, or other classroom record before sharing."
        }
    }
}
