import Foundation
@preconcurrency import CoreData
import CloudKit
import OSLog

/// Puts each classroom record this device creates into the classroom share,
/// as it is created.
///
/// Watches view-context saves — every place that creates a student,
/// attendance record, school-calendar day or day lock saves there: the
/// screens, MCP writes, restore, CSV import and `SchoolCalendarService` — and
/// takes the classroom-share types (`CoreDataStack.sharedEntityNames`) that
/// the save *inserted* into the lead guide's private store. Those, and only
/// those, go to the pinned share.
///
/// It never looks for records that merely look unshared. That sweep ran after
/// every save, launch, import and reset until 2026-09-28, and mid-download a
/// zone's rows land before its CKShare, so they read as orphans: a post-reset
/// pass moved 4,003 of them into the wrong share, which is how the classroom
/// split across zones.
///
/// Before the pin is known — a new device still downloading, where the
/// membership row hasn't arrived — the new records wait in a small persisted
/// list and are attached once it shows up. Once the first download has
/// finished with no pin, the classroom simply isn't shared yet: nothing waits,
/// because Set Up Classroom Sharing shares everything.
final class SharedStoreOrphanGuard {

    static let shared = SharedStoreOrphanGuard()

    private static let logger = Logger.sharedStoreOrphanGuard

    /// Most records kept waiting for a pin. A restore into a notebook whose
    /// pin hasn't arrived could otherwise queue a whole classroom.
    static let maxPending = 20_000

    private weak var coreDataStack: CoreDataStack?
    private var saveObservation: NotificationCenter.ObservationToken?
    private var flushTask: Task<Void, Never>?
    private var flushing = false
    private var flushAgain = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Begins observing view-context saves. Idempotent.
    func start(coreDataStack: CoreDataStack) {
        guard saveObservation == nil else { return }
        self.coreDataStack = coreDataStack

        // The view context saves on the main queue, which is what the typed
        // `DidSaveMessage` requires; it arrives once per save, on the main
        // actor, with the saved objects in hand.
        saveObservation = NotificationCenter.default.addObserver(
            of: coreDataStack.viewContext, for: .didSave
        ) { [weak self] message in
            guard let self, let stack = self.coreDataStack else { return }
            let ids = Self.classroomInserts(message.inserted, privateStore: stack.privatePersistentStore)
            guard !ids.isEmpty else { return }
            self.handleInserts(ids, in: stack)
        }
        Self.logger.debug("SharedStoreOrphanGuard observing view-context saves")
    }

    /// The classroom-share types among `inserted` that landed in the lead
    /// guide's private store. An assistant's records go to the shared store
    /// and are attached by the companion itself.
    static func classroomInserts(
        _ inserted: Set<NSManagedObject>,
        privateStore: NSPersistentStore?
    ) -> [NSManagedObjectID] {
        guard let privateStore else { return [] }
        return inserted
            .filter { CoreDataStack.sharedEntityNames.contains($0.objectID.entity.name ?? "") }
            .map(\.objectID)
            .filter { $0.persistentStore === privateStore && !$0.isTemporaryID }
    }

    // MARK: - Save handling

    private func handleInserts(_ ids: [NSManagedObjectID], in stack: CoreDataStack) {
        guard stack.isCloudKitActive else { return }
        let context = stack.viewContext
        guard Self.shouldTrack(
            role: CDClassroomMembership.currentRole(in: context),
            pinKnown: CDClassroomMembership.pinnedZoneName(in: context) != nil,
            firstDownloadPending: FirstDownloadGate.isPending()
        ) else { return }
        enqueue(ids)
        flushPendingIfPossible()
    }

    /// Whether this device's new classroom records are the guard's to attach:
    /// the lead guide's, with the share pinned or possibly still on its way
    /// down. No pin once the notebook has fully downloaded means not shared
    /// yet — setup will take everything, these included.
    static func shouldTrack(
        role: CDClassroomMembership.ClassroomRole,
        pinKnown: Bool,
        firstDownloadPending: Bool
    ) -> Bool {
        role == .leadGuide && (pinKnown || firstDownloadPending)
    }

    // MARK: - Waiting list

    private static var pendingKey: String { UserDefaultsKeys.classroomSharePendingAttach }

    /// URIs of records waiting to be attached.
    var pendingURIs: [String] {
        defaults.stringArray(forKey: Self.pendingKey) ?? []
    }

    func enqueue(_ ids: [NSManagedObjectID]) {
        var pending = pendingURIs
        let known = Set(pending)
        pending.append(contentsOf: ids.map { $0.uriRepresentation().absoluteString }.filter { !known.contains($0) })
        if pending.count > Self.maxPending {
            let dropped = pending.count - Self.maxPending
            Self.logger.error("Classroom attach list full: \(dropped, privacy: .public) oldest dropped")
            pending.removeFirst(dropped)
        }
        defaults.set(pending, forKey: Self.pendingKey)
    }

    /// Forgets the waiting list. Set Up Classroom Sharing calls this: it has
    /// just shared everything the list could hold.
    func clearPending() {
        defaults.removeObject(forKey: Self.pendingKey)
    }

    // MARK: - Attaching

    /// Attaches whatever is waiting, once it can: the first download done,
    /// the pinned share in the store, CloudKit healthy. Called after saves,
    /// at the end of launch, and when the first download finishes.
    func flushPendingIfPossible() {
        guard flushTask == nil else {
            flushAgain = true
            return
        }
        flushTask = Task { [weak self] in
            // Let a burst of saves collect into one pass.
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            repeat {
                self.flushAgain = false
                await self.flush()
            } while self.flushAgain
            self.flushTask = nil
        }
    }

    private func flush() async {
        guard let stack = coreDataStack, stack.isCloudKitActive,
              let store = stack.privatePersistentStore else { return }
        let taken = pendingURIs
        guard !taken.isEmpty else { return }
        guard !FirstDownloadGate.isPending(),
              !CloudKitSyncStatusService.shared.mirroringDelegateFailed else { return }
        let context = stack.viewContext
        guard CDClassroomMembership.pinnedZoneName(in: context) != nil else {
            // Downloaded, and still no pin: the classroom isn't shared.
            let count = taken.count
            Self.logger.notice("No classroom share after the first download; \(count, privacy: .public) left to setup")
            clearPending()
            return
        }
        let container = stack.container
        let share: CKShare?
        do {
            share = try ClassroomShareAttach.classroomShare(in: store, container: container, pinContext: context)
        } catch {
            Self.logger.error("Couldn't read the classroom share: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Pinned, but its CKShare hasn't imported yet: keep waiting.
        guard let share else { return }

        let existing = await Self.existingIDs(for: taken, container: container)
        let waiting: [NSManagedObjectID]
        do {
            waiting = try await ClassroomShareAttach.unshared(existing, container: container)
        } catch {
            let detail = error.localizedDescription
            Self.logger.error("Couldn't check which records are shared: \(detail, privacy: .public)")
            return
        }
        let outcome = await ClassroomShareAttach.attach(waiting, to: share, container: container)
        if outcome.mirroringDelegateDied {
            CloudKitSyncStatusService.shared.mirroringDelegateFailed = true
        }
        // Keep what failed and anything enqueued while this pass ran.
        let takenSet = Set(taken)
        let failed = outcome.failed.map { $0.uriRepresentation().absoluteString }
        let remaining = pendingURIs.filter { !takenSet.contains($0) } + failed
        if remaining.isEmpty { clearPending() } else { defaults.set(remaining, forKey: Self.pendingKey) }
        let summary = "attached \(outcome.attached), failed \(outcome.failed.count), " +
            "already shared or deleted \(taken.count - waiting.count)"
        Self.logger.notice("Classroom attach: \(summary, privacy: .public)")
    }

    /// The object IDs among `uris` whose records still exist.
    @concurrent
    private static func existingIDs(
        for uris: [String],
        container: NSPersistentCloudKitContainer
    ) async -> [NSManagedObjectID] {
        let coordinator = container.persistentStoreCoordinator
        let ids = uris.compactMap { URL(string: $0).flatMap(coordinator.managedObjectID(forURIRepresentation:)) }
        let context = container.newBackgroundContext()
        return await context.perform {
            ids.filter { (try? context.existingObject(with: $0)) != nil }
        }
    }
}
