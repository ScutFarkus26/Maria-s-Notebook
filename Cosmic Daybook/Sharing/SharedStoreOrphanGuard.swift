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
/// those, go to the pinned share. Siri's saves also come in by `siriDidSave`:
/// an intent run in the background brings up no window, so no bootstrap
/// starts this.
///
/// It never looks for records that merely look unshared. That sweep ran after
/// every save, launch, import and reset until 2026-09-28, and mid-download a
/// zone's rows land before its CKShare, so they read as orphans: a post-reset
/// pass moved 4,003 of them into the wrong share, which is how the classroom
/// split across zones.
///
/// Until they can be attached — before the pin is known (a new device still
/// downloading, or the guide's iPad in the minutes before the Mac's setup
/// reaches it), with iCloud sync off, or during the first download — the new
/// records wait in a small persisted list (`+WaitingList`) and are attached
/// once they can be (a remote change, the end of the first download, or launch
/// sets off the attempt). Set Up Classroom Sharing on this device takes
/// everything anyway, so it forgets the entries it found, except those its
/// attach failed on; when the pin was made on another device, this device
/// forgets what it listed before then (`forgetWhatSetupElsewhereTook`).
final class SharedStoreOrphanGuard {

    static let shared = SharedStoreOrphanGuard()

    static let logger = Logger.sharedStoreOrphanGuard

    /// Most records kept waiting while the classroom isn't shared. A notebook
    /// that is never shared would otherwise grow the list forever.
    static let maxPending = 2_000

    // Internal rather than private only so the extensions in the other
    // `SharedStoreOrphanGuard+` files can reach them.
    weak var coreDataStack: CoreDataStack?
    let defaults: UserDefaults
    /// The last stamp handed out, so two adds in one instant still differ.
    var lastStamp: TimeInterval = 0
    var pruneTask: Task<Void, Never>?
    /// Which school year the share holds; a test sets its own.
    var scope: () -> ClassroomShareScope = { ClassroomShareScope() }
    /// The lock every attach on this device takes; a test sets its own.
    var attachLock = ClassroomShareAttachLock.shared
    /// How long the guard waits for one pass. Only the waiting stops:
    /// `container.share(_:to:)` can block for good and can't be cancelled, so
    /// the pass keeps the attach lock until it returns. A test sets its own.
    var attachPassTimeout: Duration = .seconds(120)

    private var saveObservation: NotificationCenter.ObservationToken?
    private var remoteChangeTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var flushAgain = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Begins observing `coreDataStack`'s view-context saves. Idempotent for
    /// one stack; started with another (a test's, or a rebuilt store), it
    /// follows that one instead.
    func start(coreDataStack stack: CoreDataStack) {
        if saveObservation != nil {
            if coreDataStack === stack { return }
            stopObserving()
        }
        coreDataStack = stack

        // The view context saves on the main queue, which is what the typed
        // `DidSaveMessage` requires; it arrives once per save, on the main
        // actor, with the saved objects in hand.
        saveObservation = NotificationCenter.default.addObserver(
            of: stack.viewContext, for: .didSave
        ) { [weak self] message in
            guard let self, let stack = self.coreDataStack else { return }
            let ids = Self.classroomInserts(message.inserted, privateStore: stack.privatePersistentStore)
                + Self.returningStudentRecords(message.updated, in: stack)
            guard !ids.isEmpty else { return }
            self.handleSaved(ids, in: stack)
        }
        // The pin (a membership row) and the share arrive by import. While
        // anything is waiting, each remote change is a chance they're here.
        let coordinator = stack.container.persistentStoreCoordinator
        remoteChangeTask = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: .NSPersistentStoreRemoteChange, object: coordinator)
                .map { _ in () }
            for await _ in changes {
                guard let self, !self.pendingURIs.isEmpty else { continue }
                self.flushPendingIfPossible()
            }
        }
        Self.logger.debug("SharedStoreOrphanGuard observing view-context saves")
    }

    private func stopObserving() {
        if let saveObservation { NotificationCenter.default.removeObserver(saveObservation) }
        saveObservation = nil
        remoteChangeTask?.cancel()
        remoteChangeTask = nil
    }

    // MARK: - Save handling

    /// Queued whether or not iCloud sync is on: a record made with sync off
    /// still belongs in the share once sync is back.
    private func handleSaved(_ ids: [NSManagedObjectID], in stack: CoreDataStack) {
        // An assistant's records go to the shared store and attach themselves.
        guard CDClassroomMembership.currentRole(in: stack.viewContext) == .leadGuide else { return }
        enqueue(ids)
        flushPendingIfPossible()
    }

    /// Siri's way in. An attendance intent run in the background brings up no
    /// window, so the bootstrap that starts this may never have run: it starts
    /// here, the records Siri just created are queued (if the save observer was
    /// already running it queued them too, and a repeat is one entry), and the
    /// pass runs while Siri keeps the app awake (`SiriSyncKeepAlive`).
    func siriDidSave(created: [NSManagedObjectID], in stack: CoreDataStack) async {
        start(coreDataStack: stack)
        let ids = Self.classroomIDs(created, privateStore: stack.privatePersistentStore)
        guard !ids.isEmpty else { return }
        handleSaved(ids, in: stack)
        await waitUntilIdle()
    }

    /// Returns once no attach pass is running or due.
    func waitUntilIdle() async {
        while let flushTask {
            await flushTask.value
        }
    }

    // MARK: - Attaching

    /// Attaches whatever is waiting, once it can: iCloud sync on, the first
    /// download done, the pinned share in the store, CloudKit healthy. Called
    /// after saves, at the end of launch, and when the first download finishes.
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
              let store = stack.privatePersistentStore,
              !pendingURIs.isEmpty else { return }
        // A second copy of the app (the Mac can run several) only queues: the
        // attach lock below is this process's only, so two copies could each
        // find a record unshared and share it twice. The first copy reads the
        // same waiting list and attaches it at its next save or remote change,
        // and this copy takes over once the others have quit.
        if CoreDataStack.isSecondaryProcess {
            AppBootstrapper.takeOverIfAlone(coreDataStack: stack)
            guard !CoreDataStack.isSecondaryProcess else { return }
        }
        guard !FirstDownloadGate.isPending(),
              !CloudKitSyncStatusService.shared.mirroringDelegateFailed else { return }
        // No pin yet: not shared, or the setup hasn't reached this device.
        // Keep waiting; setup here, or the pin's arrival, settles it.
        guard let pin = CDClassroomMembership.current(in: stack.viewContext),
              !pin.classroomZoneID.isEmpty else { return }
        forgetWhatSetupElsewhereTook(pinnedZone: pin.classroomZoneID, pinnedAt: pin.modifiedAt ?? pin.joinedAt)
        // A pin from another device: wait for an import that began after it
        // arrived, so what setup there shared reads as shared here. The next
        // remote change tries again.
        guard !waitingForImportAfterPin(notebookStoreID: store.identifier) else { return }

        await attachWaiting { [weak self] taken in
            await self?.attachToPinnedShare(taken, storeID: store.identifier)
        }
    }

    /// Takes the attach lock and runs `pass` over what is waiting. Never
    /// beside Set Up Classroom Sharing (and "Add them to the share") or the
    /// one-time attendance step: two passes could each find a record unshared
    /// and ask CloudKit to share it twice.
    ///
    /// Waits for `pass` at most `attachPassTimeout`, so one attach that never
    /// returns doesn't hold up filing (and Siri's wait for it) until the next
    /// launch. The pass keeps the lock until it does return, and anything
    /// waiting stays listed: each later attempt finds the lock stuck and
    /// leaves without waiting, and the late pass looks again when it ends.
    func attachWaiting(_ pass: @escaping @Sendable @MainActor ([Entry]) async -> Void) async {
        let lock = attachLock
        guard await lock.acquireUnlessStuck() else {
            Self.logger.notice("Classroom attach: an earlier pass hasn't returned; records stay listed")
            return
        }
        let taken = pendingEntries
        guard !taken.isEmpty else {
            lock.release()
            return
        }
        let returned = await lock.hand(
            to: { await pass(taken) },
            waitingAtMost: attachPassTimeout,
            afterStuck: { [weak self] in
                guard let self, !self.pendingURIs.isEmpty else { return }
                Self.logger.notice("Classroom attach: the late pass returned; trying what's listed")
                self.flushPendingIfPossible()
            }
        )
        if !returned {
            let seconds = attachPassTimeout.components.seconds
            Self.logger.error(
                "Classroom attach pass still running after \(seconds, privacy: .public) s; records stay listed"
            )
        }
    }

    /// One pass, holding the attach lock: reads the pinned share and attaches
    /// what belongs.
    private func attachToPinnedShare(_ taken: [Entry], storeID: String) async {
        guard let stack = coreDataStack else { return }
        let share: CKShare?
        do {
            // Off the main actor: `fetchShares(in:)` waits while an import or
            // export holds the store.
            share = try await ClassroomShareAttach.classroomShare(
                inStoreWithIdentifier: storeID, container: stack.container, pinContext: stack.viewContext
            )
        } catch {
            Self.logger.error("Couldn't read the classroom share: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Pinned, but its CKShare hasn't imported yet: keep waiting.
        guard let share else { return }
        await attach(taken, to: share, storeID: storeID, container: stack.container)
    }

    /// One pass over `taken`. This school year only (`ClassroomShareScope`): a
    /// mark on a past year's day, a student who left in an earlier year, or a
    /// restore of either stays in the notebook. A returning student found
    /// unshared brings this year's attendance with her.
    private func attach(
        _ taken: [Entry], to share: CKShare, storeID: String, container: NSPersistentCloudKitContainer
    ) async {
        let scope = self.scope()
        let sorted = await Self.sort(taken.map(\.uri), container: container, scope: scope)
        let waiting: [NSManagedObjectID]
        do {
            let unshared = try await ClassroomShareAttach.unshared(sorted.belonging, container: container)
            let returning = await Self.thisYearsAttendance(
                ofStudents: unshared.filter { $0.entity.name == "Student" },
                storeID: storeID, container: container, scope: scope
            )
            let listed = Set(unshared)
            let alongside = try await ClassroomShareAttach.unshared(
                returning.filter { !listed.contains($0) }, container: container
            )
            waiting = unshared + alongside
        } catch {
            let detail = error.localizedDescription
            Self.logger.error("Couldn't check which records are shared: \(detail, privacy: .public)")
            return
        }
        let outcome = await ClassroomShareAttach.attach(waiting, to: share, container: container)
        if outcome.mirroringDelegateDied {
            CloudKitSyncStatusService.shared.mirroringDelegateFailed = true
        }
        // Keep what failed, anything added again meanwhile, and, until the
        // school-year start reaches this device, what looked like last year's.
        let failed = outcome.failed.map { $0.uriRepresentation().absoluteString }
        forget(taken, except: Set(failed).union(scope.isProvisional ? sorted.outsideScope : []))
        let stillListed = Set(pendingURIs)
        add(failed.filter { !stillListed.contains($0) })
        let summary = "attached \(outcome.attached), failed \(outcome.failed.count), " +
            "already shared, deleted or outside this school year \(taken.count - sorted.belonging.count)"
        Self.logger.notice("Classroom attach: \(summary, privacy: .public)")
    }
}
