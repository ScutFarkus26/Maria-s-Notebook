import Foundation
import CoreData
import OSLog

/// Watches view-context saves and reacts whenever a shared-store entity
/// is inserted so it never becomes an orphan that poisons
/// `NSCloudKitMirroringDelegate` (`NSCocoaErrorDomain 134060`).
///
/// Two cases:
///
/// 1. **No `CKShare` yet** — invokes
///    `ClassroomSharingService.ensureShareExistsOnLaunch`, which creates
///    a share seeded from existing shared-store records and then sweeps
///    the orphans in via `SharedStoreZoneRepair`.
///
/// 2. **Share already exists** — debounces a call to
///    `SharedStoreZoneRepair.runIfNeeded`. The repair pass is idempotent
///    and cheap when there are no orphans, but new inserts can land
///    outside any zone if a feature path creates a shared-store record
///    without first checking. The debounce avoids running the repair
///    once per insert during bulk writes.
///
/// This class is the safety net behind Changes 1-3 in the
/// shared-store-orphans fix: those gates stop the known offenders,
/// while this observer catches anything a future contributor adds.
final class SharedStoreOrphanGuard {

    static let shared = SharedStoreOrphanGuard()

    private static let logger = Logger.sharedStoreOrphanGuard

    private weak var coreDataStack: CoreDataStack?
    private var saveObservation: NotificationCenter.ObservationToken?
    private var debounceTask: Task<Void, Never>?

    private init() {}

    /// Begins observing view-context saves. Idempotent — calling more
    /// than once is a no-op.
    func start(coreDataStack: CoreDataStack) {
        guard saveObservation == nil else { return }
        self.coreDataStack = coreDataStack

        // The view context saves on the main queue, which is what the typed
        // `DidSaveMessage` requires; it arrives once per save, on the main
        // actor, with the saved objects in hand.
        saveObservation = NotificationCenter.default.addObserver(
            of: coreDataStack.viewContext, for: .didSave
        ) { [weak self] message in
            let names = Set(message.inserted.compactMap { $0.objectID.entity.name })
            guard !names.isEmpty else { return }
            self?.handleSave(insertedEntityNames: names)
        }
        Self.logger.debug("SharedStoreOrphanGuard observing view-context saves")
    }

    // MARK: - Save handling

    private func handleSave(insertedEntityNames: Set<String>) {
        guard let coreDataStack else { return }
        guard coreDataStack.isCloudKitActive else { return }
        // Neither repair nor auto-create may act on a store still receiving
        // its first download; the gate's opening runs the repair itself.
        guard !FirstDownloadGate.isPending() else { return }

        let touchedSharedStore = !insertedEntityNames.isDisjoint(with: CoreDataStack.sharedEntityNames)
        guard touchedSharedStore else { return }

        // If a previous repair attempt hit CloudKit's 10-minute
        // Share-Export timeout, don't re-arm auto-runs — they'd just block
        // Core Data's serial queue for another 10 minutes per cycle. The
        // user can trigger a manual run via Settings → Repair Sync Errors
        // when CloudKit is healthy again.
        guard !SharedStoreZoneRepair.isCircuitBreakerOpen else { return }

        if SharedStoreZoneRepair.shared.hasActiveShare {
            scheduleRepair(coreDataStack: coreDataStack)
        } else {
            scheduleAutoCreate(coreDataStack: coreDataStack)
        }
    }

    /// Debounces a repair pass so bulk writes (e.g. seeding curriculum)
    /// trigger at most one repair after the write storm settles.
    private func scheduleRepair(coreDataStack: CoreDataStack) {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
            await SharedStoreZoneRepair.runIfNeeded(coreDataStack: coreDataStack)
        }
    }

    /// Debounces the auto-create flow the same way. The flow itself is
    /// idempotent (it checks `hasActiveShare` before doing any work) so
    /// duplicates from rapid saves are safe.
    private func scheduleAutoCreate(coreDataStack: CoreDataStack) {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
            await ClassroomSharingService.ensureShareExistsOnLaunch(coreDataStack: coreDataStack)
        }
    }
}
