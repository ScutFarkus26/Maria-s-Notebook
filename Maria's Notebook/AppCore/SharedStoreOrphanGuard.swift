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
@MainActor
final class SharedStoreOrphanGuard {

    static let shared = SharedStoreOrphanGuard()

    private static let logger = Logger.app(category: "SharedStoreOrphanGuard")

    private weak var coreDataStack: CoreDataStack?
    private var observer: (any NSObjectProtocol)?
    private var debounceTask: Task<Void, Never>?

    private init() {}

    /// Begins observing view-context saves. Idempotent — calling more
    /// than once is a no-op.
    func start(coreDataStack: CoreDataStack) {
        guard observer == nil else { return }
        self.coreDataStack = coreDataStack

        let context = coreDataStack.viewContext
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: context,
            queue: .main
        ) { [weak self] notification in
            // Extract Sendable data from the notification BEFORE
            // crossing the isolation boundary — Notification and
            // NSManagedObject are not Sendable. We only need the set of
            // inserted entity names to decide whether to act.
            let inserted = (notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
            var insertedEntityNames: Set<String> = []
            for object in inserted {
                if let name = object.entity.name {
                    insertedEntityNames.insert(name)
                }
            }
            guard !insertedEntityNames.isEmpty else { return }

            Task { @MainActor [weak self] in
                self?.handleSave(insertedEntityNames: insertedEntityNames)
            }
        }
        Self.logger.debug("SharedStoreOrphanGuard observing view-context saves")
    }

    /// Stops observing. Used in tests and when the stack is replaced.
    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        debounceTask?.cancel()
        debounceTask = nil
        coreDataStack = nil
    }

    // MARK: - Save handling

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
        debounceTask = Task { @MainActor in
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
        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
            await ClassroomSharingService.ensureShareExistsOnLaunch(coreDataStack: coreDataStack)
        }
    }
}
