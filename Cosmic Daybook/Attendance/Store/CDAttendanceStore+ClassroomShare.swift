import Foundation
@preconcurrency import CoreData
import CloudKit
import OSLog

// MARK: - An assistant's new records go into the classroom share
//
// On the lead guide's device a new mark lands in the private store and
// `SharedStoreOrphanGuard` attaches it to the classroom share. An assistant's
// mark lands in the shared store (`CDAttendanceStore.destinationStore`), and
// until 2026-09-28 which share zone it joined was left to Core Data. It is now
// put into the classroom share explicitly, right after the save that creates
// it: the pinned share, or — an assistant's shared store holding one share in
// the two-zone layout — the only share there is.
//
// Whether CloudKit accepts `share(_:to:)` from a participant for a record the
// participant created is one of the things Part 2 of the Production move tests;
// every outcome is logged, and a failure leaves the record where Core Data put it.

extension CDAttendanceStore {

    /// How one try at putting new records into the classroom share went.
    nonisolated struct ShareAttachResult: Sendable {
        /// The records to try again later.
        var left: [NSManagedObjectID]
        /// CloudKit mirroring died this session (`ClassroomShareAttach`
        /// `mirroringDelegateDied`): every later `share(_:to:)` on this
        /// container fails the same way, by an exception no `catch` traps,
        /// so nothing may try again until the stack is rebuilt or relaunched.
        var mirroringStopped = false
        /// The try stopped because iCloud couldn't be reached
        /// (`ClassroomShareAttach.Outcome.noConnection`).
        var noConnection = false
        /// CloudKit asked for this many seconds before the next try.
        var retryAfter: TimeInterval?
        /// There was no classroom share to put them in: on a phone that has
        /// just joined, it hasn't come down yet. Its arrival is the moment to
        /// try again (`AssistantShareAttacher.shareArrived`, bug hunt
        /// 2026-11-02 #44), not the end of a rest.
        var noShare = false
    }

    private static let shareLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CosmicDaybook",
        category: "AttendanceShare"
    )

    /// Puts `ids` — attendance records (or day locks) this device just saved
    /// into the shared store — into the classroom share. Records already in a
    /// share are left alone. Returns the ones to try again later (those that
    /// failed, and all of them when there is no share to put them in yet or
    /// it couldn't be read), and whether mirroring stopped.
    ///
    /// A container with no stores open is a stack closed for a rebuild
    /// (`AssistantStack.rebuild`), not a sign there's nothing to do: its
    /// records wait for the new stack. Reading that as "done" dropped them.
    /// (A stack open on one store, as in tests, has no share to put
    /// anything in.)
    ///
    /// `stopReason` is asked before each chunk (`ClassroomShareAttach`): the
    /// Daybook Assistant's hold on a store whose setup failed or whose sync
    /// stopped (`AssistantFilingHold`, 2026-10-10 review, #1). What it stops
    /// is left to try again.
    @discardableResult
    static func attachNewRecordsToClassroomShare(
        _ ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer,
        pinContext: NSManagedObjectContext,
        stopReason: @escaping @Sendable () async -> String? = { nil }
    ) async -> ShareAttachResult {
        let stores = container.persistentStoreCoordinator.persistentStores
        guard !stores.isEmpty else {
            shareLogger.notice("No store open; \(ids.count, privacy: .public) record(s) wait for the next try")
            return ShareAttachResult(left: ids.filter { !$0.isTemporaryID })
        }
        let sharedStore = stores.first { $0.configurationName == CoreDataStack.sharedConfiguration }
        let permanent = ids.filter { !$0.isTemporaryID && $0.persistentStore === sharedStore }
        guard let sharedStore, let sharedStoreID = sharedStore.identifier, !permanent.isEmpty else {
            return ShareAttachResult(left: [])
        }

        // Read off the main actor: this runs right after the save that created
        // the records, while CloudKit's export of that save may hold the store.
        let share: CKShare?
        do {
            share = try await ClassroomShareAttach.classroomShare(
                inStoreWithIdentifier: sharedStoreID,
                container: container,
                pinContext: pinContext,
                onlyShareFallback: true
            )
        } catch {
            shareLogger.error("Couldn't read the classroom share: \(error.localizedDescription, privacy: .public)")
            return ShareAttachResult(left: permanent)
        }
        guard let share else {
            shareLogger.error("No classroom share to put \(permanent.count, privacy: .public) new record(s) into")
            return ShareAttachResult(left: permanent, noShare: true)
        }
        do {
            let waiting = try await ClassroomShareAttach.unshared(permanent, container: container)
            guard !waiting.isEmpty else {
                shareLogger.info("New record(s) already in the classroom share")
                return ShareAttachResult(left: [])
            }
            let outcome = await ClassroomShareAttach.attach(
                waiting, to: share, container: container, stopReason: stopReason
            )
            let summary = "attached \(outcome.attached), failed \(outcome.failed.count)" +
                (outcome.stoppedBecause.map { ", stopped: \($0)" } ?? "")
            shareLogger.notice("Assistant records to classroom share: \(summary, privacy: .public)")
            return ShareAttachResult(
                left: outcome.failed,
                mirroringStopped: outcome.mirroringDelegateDied,
                noConnection: outcome.noConnection,
                retryAfter: outcome.retryAfter
            )
        } catch {
            shareLogger.error("Couldn't check the new records' share: \(error.localizedDescription, privacy: .public)")
            return ShareAttachResult(left: permanent)
        }
    }

    /// The share zone each of `ids` is in, read off the caller's actor: a
    /// record in no share has no entry. Throws when CloudKit can't say.
    @concurrent
    nonisolated static func shareZoneNames(
        of ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer
    ) async throws -> [NSManagedObjectID: String] {
        guard !ids.isEmpty else { return [:] }
        return try container.fetchShares(matching: ids).mapValues(\.recordID.zoneID.zoneName)
    }

    /// Deletes those of `ids` that still exist and are in no share, on a
    /// fresh background context (a view context can still hold objects a
    /// purge removed), and returns how many. For the Assistant's marks that
    /// never went into the share when she leaves: the purge takes only the
    /// class's zone. A record in a share is never deleted here: its delete
    /// would reach the guide. Throws, deleting nothing, when CloudKit can't
    /// say which are shared.
    ///
    /// The context is the stack's own (`newBackgroundContext`), with the
    /// app's author and merge policy: one straight from the container saved
    /// with no author and the error merge policy, so the delete read as
    /// another device's and a clash with a sync failed it (bug hunt
    /// 2026-11-02 #53).
    static func deleteUnsharedRecords(_ ids: [NSManagedObjectID], in stack: CoreDataStack) async throws -> Int {
        guard !ids.isEmpty else { return 0 }
        return try await deleteUnsharedRecords(ids, container: stack.container, context: stack.newBackgroundContext())
    }

    @concurrent
    private nonisolated static func deleteUnsharedRecords(
        _ ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer,
        context: NSManagedObjectContext
    ) async throws -> Int {
        let existing = context.performAndWait { ids.filter { (try? context.existingObject(with: $0)) != nil } }
        guard !existing.isEmpty else { return 0 }
        let inShare = try container.fetchShares(matching: existing)
        let outside = existing.filter { inShare[$0] == nil }
        guard !outside.isEmpty else { return 0 }
        return try context.performAndWait {
            for id in outside { context.delete(try context.existingObject(with: id)) }
            try context.save()
            return outside.count
        }
    }
}

#if !ASSISTANT_APP

// MARK: - A notebook joined as an assistant files its marks too
//
// A notebook that joined another guide's class as an assistant writes its
// marks into the shared store as the Daybook Assistant does
// (`CDAttendanceStore.destinationStore`), and until 2026-11-02 left which
// share zone they joined to Core Data, the pre-2026-09-28 way the Assistant
// was moved off: with a stale second share there it was a coin toss (bug hunt
// 2026-11-02 #33). Now each save that inserts classroom records into the
// shared store puts them into the classroom share explicitly, through the
// same attach. `SharedStoreOrphanGuard` takes only the lead guide's.

/// Watches the view context of a notebook in the assistant role, from the
/// first `CDAttendanceStore` made for one (`watch`). What a pass leaves waits,
/// in memory, for the next save that files anything or the end of a rest,
/// one pass at a time, under the attach lock everything else that files on
/// this device takes. A quit leaves it where Core Data put it, as before.
@MainActor
final class AssistantRoleShareFiling {
    static let shared = AssistantRoleShareFiling()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CosmicDaybook",
        category: "AttendanceShare"
    )

    /// One try at putting records into the share; tests pass their own.
    typealias Attempt = @MainActor (
        _ ids: [NSManagedObjectID],
        _ container: NSPersistentCloudKitContainer,
        _ context: NSManagedObjectContext
    ) async -> CDAttendanceStore.ShareAttachResult

    /// The records a pass left, oldest first.
    private(set) var waiting: [NSManagedObjectID] = []
    private let attempt: Attempt
    private let role: @MainActor (NSManagedObjectContext) -> CDClassroomMembership.ClassroomRole
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private weak var context: NSManagedObjectContext?
    private weak var container: NSPersistentCloudKitContainer?
    private var observation: NotificationCenter.ObservationToken?
    private var pass: Task<Void, Never>?
    private var runAgain = false
    private var retry: Task<Void, Never>?
    private var failuresInARow = 0
    /// CloudKit mirroring died on the watched container: every later
    /// `share(_:to:)` on it would raise an exception no `catch` traps, so
    /// nothing more is tried this session.
    private var mirroringStopped = false

    init(
        attempt: @escaping Attempt = { ids, container, context in await liveAttempt(ids, container, context) },
        role: @escaping @MainActor (NSManagedObjectContext) -> CDClassroomMembership.ClassroomRole = {
            CDClassroomMembership.currentRole(in: $0)
        },
        sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.attempt = attempt
        self.role = role
        self.sleep = sleep
    }

    /// The attach, under the holds and the stop every other filer in the
    /// notebook honors (`CloudKitSyncStatusService.shareFilingStopReason`):
    /// `share(_:to:)` on a store whose mirroring died raises an exception no
    /// `catch` traps. A stop it finds itself is told to the sync status.
    static func liveAttempt(
        _ ids: [NSManagedObjectID], _ container: NSPersistentCloudKitContainer, _ context: NSManagedObjectContext
    ) async -> CDAttendanceStore.ShareAttachResult {
        let result = await CDAttendanceStore.attachNewRecordsToClassroomShare(
            ids, container: container, pinContext: context,
            stopReason: CloudKitSyncStatusService.sharedFilingStopReason
        )
        if result.mirroringStopped, let storeID = container.persistentStoreCoordinator.persistentStores
            .first(where: { $0.configurationName == CoreDataStack.sharedConfiguration })?.identifier {
            CloudKitSyncStatusService.shared.markMirroringStopped(byAttachToStoreWithIdentifier: storeID)
        }
        return result
    }

    /// Follows `context`'s saves from now on: the main-queue view context of
    /// the stack `container` belongs to. Once per context.
    func watch(_ context: NSManagedObjectContext, container: NSPersistentCloudKitContainer) {
        guard context.concurrencyType == .mainQueueConcurrencyType, context !== self.context else { return }
        if let observation { NotificationCenter.default.removeObserver(observation) }
        self.context = context
        self.container = container
        waiting = []
        mirroringStopped = false
        observation = NotificationCenter.default.addObserver(of: context, for: .didSave) { [weak self] message in
            self?.saved(message.inserted)
        }
    }

    /// Returns once no pass is running.
    func waitUntilIdle() async {
        while let pass { await pass.value }
    }

    /// The classroom records a save put into the shared store, while the
    /// notebook is in the assistant role.
    private func saved(_ inserted: Set<NSManagedObject>) {
        guard let context, let container, !mirroringStopped else { return }
        let sharedStore = container.persistentStoreCoordinator.persistentStores
            .first { $0.configurationName == CoreDataStack.sharedConfiguration }
        let ids = inserted.map(\.objectID).filter {
            !$0.isTemporaryID && $0.persistentStore === sharedStore
                && CoreDataStack.sharedEntityNames.contains($0.entity.name ?? "")
        }
        guard !ids.isEmpty, role(context) == .assistant else { return }
        for id in ids where !waiting.contains(id) { waiting.append(id) }
        file()
    }

    private func file() {
        guard pass == nil else {
            runAgain = true
            return
        }
        retry?.cancel()
        retry = nil
        pass = Task { [weak self] in
            await self?.run()
            self?.pass = nil
        }
    }

    private func run() async {
        repeat {
            runAgain = false
            guard let context, let container, !mirroringStopped, !waiting.isEmpty else { return }
            let taken = waiting
            let attempt = attempt
            guard let result = await ClassroomShareAttachLock.shared.runUnlessStuck({
                await attempt(taken, container, context)
            }) else {
                Self.logger.notice("Another attach is stuck; \(taken.count, privacy: .public) mark(s) wait")
                rest(retryAfter: nil)
                return
            }
            // Saved during the pass stay; of these, only what failed.
            let left = Set(result.left)
            let tried = Set(taken)
            waiting = waiting.filter { !tried.contains($0) || left.contains($0) }
            if result.mirroringStopped {
                let unfiled = waiting.count
                Self.logger.error("CloudKit mirroring stopped; \(unfiled, privacy: .public) mark(s) stay unfiled")
                mirroringStopped = true
                return
            }
            if left.isEmpty {
                failuresInARow = 0
            } else {
                rest(retryAfter: result.retryAfter)
            }
        } while runAgain
    }

    /// After a pass that left marks: one minute, doubling, never more than
    /// ten, and never before CloudKit's own wait ends.
    private func rest(retryAfter: TimeInterval?) {
        failuresInARow += 1
        let seconds = max(min(60 * pow(2, Double(failuresInARow - 1)), 10 * 60), retryAfter ?? 0)
        retry?.cancel()
        retry = Task { [weak self, sleep] in
            do { try await sleep(seconds) } catch { return }
            guard !Task.isCancelled else { return }
            self?.file()
        }
    }
}

#endif
