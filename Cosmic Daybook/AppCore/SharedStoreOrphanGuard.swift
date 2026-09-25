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
    private var observerTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    private init() {}

    /// Begins observing view-context saves. Idempotent — calling more
    /// than once is a no-op.
    func start(coreDataStack: CoreDataStack) {
        guard observerTask == nil else { return }
        self.coreDataStack = coreDataStack

        observerTask = Task { [weak self] in
            guard let context = self?.coreDataStack?.viewContext else { return }
            // Extract Sendable data from each notification before it
            // reaches this main-actor loop — Notification and
            // NSManagedObject are not Sendable. We only need the set of
            // inserted entity names to decide whether to act.
            let saves = NotificationCenter.default
                .notifications(named: .NSManagedObjectContextDidSave, object: context)
                .map { Self.insertedEntityNames(in: $0) }
            for await names in saves where !names.isEmpty {
                self?.handleSave(insertedEntityNames: names)
            }
        }
        Self.logger.debug("SharedStoreOrphanGuard observing view-context saves")
    }

    // MARK: - Save handling

    /// Entity names of the objects a did-save notification reports as
    /// inserted — read off object IDs so the sequence's transform is safe on
    /// any thread.
    private nonisolated static func insertedEntityNames(in notification: Notification) -> Set<String> {
        let inserted = (notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
        var names: Set<String> = []
        for object in inserted {
            if let name = object.objectID.entity.name {
                names.insert(name)
            }
        }
        return names
    }

    private func handleSave(insertedEntityNames: Set<String>) {
        guard let coreDataStack else { return }
        guard coreDataStack.isCloudKitActive else { return }

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
