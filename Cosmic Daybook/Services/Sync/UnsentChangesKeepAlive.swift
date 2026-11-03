//
//  UnsentChangesKeepAlive.swift
//  Cosmic Daybook
//
//  iOS suspends an app a few seconds after it leaves the foreground. A mark
//  tapped just before the phone is locked would then sit on the device until
//  the next launch or a background wake, and the other devices wouldn't see
//  it. This keeps the app awake after it leaves, until CloudKit has exported
//  what was saved (at most 25 s, the app's own sending included), and only
//  when something is waiting to go.
//
//  Shared with Daybook Assistant, which compiles this file by path. It stays
//  on classic notifications: the Assistant supports iOS 18.
//

import CoreData
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class UnsentChangesKeepAlive {
    /// iOS allows about 30 s of background time.
    static let limit: Duration = .seconds(25)

    /// Waits out a limit; tests pass their own.
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private static var installed: UnsentChangesKeepAlive?

    /// Per store, by identifier: when the view context last saved changes to
    /// it, while no finished export of that store has covered that save. An
    /// export counts only if it started after the newest save. Keeping the
    /// first save instead let an export that began between two saves cover
    /// both (2026-10-05): she marks A, an upload starts, she marks B, the
    /// upload finishes, and Leave counted B as gone. And only that store's
    /// export: in the notebook any store's export ended the wait, so the
    /// private store's could let the iPad sleep while the classroom share's,
    /// which carries the mark the Assistant needs, was still to go (bug hunt
    /// 2026-11-02, #25). An object whose store isn't known is kept under
    /// `anyStore`, which any store's export covers.
    private(set) var unsentSinceByStore: [String: Date] = [:]

    /// The key for a saved object whose store isn't known.
    nonisolated static let anyStore = ""

    /// The newest save still waiting for its store's export, or nil.
    var unsentSince: Date? { unsentSinceByStore.values.max() }
    private let isBusy: @MainActor () -> Bool
    private let hasWaitingWork: @MainActor () -> Bool
    private let waitForWork: @MainActor () async -> Void
    private let sleep: Sleep
    /// Written in `init` only; read again in `deinit`.
    private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Watches `stack` from now on, replacing whatever was watched before.
    /// `isBusy` and `waitForWork` add the app's own sending (the Assistant's
    /// share attach, the notebook's filing into the classroom share) to what
    /// leaving the foreground waits for.
    static func install(
        for stack: CoreDataStack,
        isBusy: @escaping @MainActor () -> Bool = { false },
        waitForWork: @escaping @MainActor () async -> Void = {}
    ) {
        installed = UnsentChangesKeepAlive(
            viewContext: stack.viewContext, isBusy: isBusy, waitForWork: waitForWork
        )
    }

    /// `hasWaitingWork`: the app's own sending has something waiting to try
    /// (the Assistant's marks resting after a failed attach). Leaving the
    /// foreground then keeps the app awake too, and `waitForWork` tries it.
    init(
        viewContext: NSManagedObjectContext,
        isBusy: @escaping @MainActor () -> Bool = { false },
        hasWaitingWork: @escaping @MainActor () -> Bool = { false },
        waitForWork: @escaping @MainActor () async -> Void = {},
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.isBusy = isBusy
        self.hasWaitingWork = hasWaitingWork
        self.waitForWork = waitForWork
        self.sleep = sleep
        let center = NotificationCenter.default
        // Delivered on the saving thread (the main one, for the view
        // context), so the time is noted before any export can start.
        observers.append(center.addObserver(
            forName: .NSManagedObjectContextDidSave, object: viewContext, queue: nil
        ) { [weak self] note in
            let stores = Self.storesLeftToUpload(in: note)
            guard !stores.isEmpty else { return }
            let now = Date()
            MainActor.assumeIsolated { self?.saved(at: now, stores: stores) }
        })
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .export, event.succeeded, event.endDate != nil else { return }
            #if ASSISTANT_APP
            // Her marks go to the classroom share: the private store's export
            // says nothing about them, and counting it let Leave purge marks
            // that hadn't gone (`AssistantBootstrapper.unsentMarks`).
            let container = note.object as? NSPersistentCloudKitContainer
            let configuration = container?.persistentStoreCoordinator.persistentStores
                .first { $0.identifier == event.storeIdentifier }?.configurationName
            guard configuration == CoreDataStack.sharedConfiguration else { return }
            #endif
            let started = event.startDate
            let store = event.storeIdentifier
            MainActor.assumeIsolated { self?.exported(startedAt: started, storeIdentifier: store) }
        })
        #if canImport(UIKit)
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didLeaveForeground() }
        })
        #endif
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Whether leaving the foreground now would leave anything behind.
    var hasUnsentWork: Bool { !unsentSinceByStore.isEmpty || isBusy() }

    /// Whether leaving the foreground now keeps the app awake: something
    /// unsent, or the app's own sending has something to try. Marks resting
    /// after a failed attach counted as neither, so the phone locked with them
    /// untried. Leave reads `hasUnsentWork`, which counts them its own way.
    var needsKeepAlive: Bool { hasUnsentWork || hasWaitingWork() }

    /// A save left something for `stores` (identifiers) to send.
    func saved(at date: Date, stores: Set<String> = [UnsentChangesKeepAlive.anyStore]) {
        for store in stores { unsentSinceByStore[store] = date }
    }

    /// A store's export that started at `start` went up: it covers that
    /// store's saves from before it started. With no store named (the
    /// tests' one-store stack), it covers every store's.
    func exported(startedAt start: Date, storeIdentifier: String? = nil) {
        let covered = unsentSinceByStore.filter { store, since in
            start >= since && (storeIdentifier == nil || store == storeIdentifier || store == Self.anyStore)
        }
        guard !covered.isEmpty else { return }
        for store in covered.keys { unsentSinceByStore[store] = nil }
        guard unsentSinceByStore.isEmpty else { return }
        settle()
    }

    /// The changes waiting to go were taken off this device (the Assistant's
    /// Leave): there is nothing left to send.
    func forgetUnsent() {
        unsentSinceByStore = [:]
        settle()
    }

    /// Everything a save changed, from its `NSManagedObjectContextDidSave`.
    nonisolated static func changedObjects(in note: Notification) -> [NSManagedObject] {
        [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].flatMap { key in
            Array((note.userInfo?[key] as? Set<NSManagedObject>) ?? [])
        }
    }

    /// Whether a save of `changed` leaves something for CloudKit to send.
    nonisolated static func leavesSomethingToSend(_ changed: [NSManagedObject]) -> Bool {
        !storesToSend(changed).isEmpty
    }

    /// The stores, by identifier, a save of `changed` leaves something for
    /// CloudKit to send from (`anyStore` for an object whose store isn't
    /// known). In the Assistant only the shared store's changes go anywhere
    /// that matters: her membership row lives in her private store, and
    /// counting it made Leave warn of unsent marks right after she joined. A
    /// stack with one store (the tests') has no other store to tell them from.
    nonisolated static func storesToSend(_ changed: [NSManagedObject]) -> Set<String> {
        let touched = changed.map { $0.objectID.persistentStore }
        #if ASSISTANT_APP
        let isShared = { (store: NSPersistentStore) in store.configurationName == CoreDataStack.sharedConfiguration }
        let stores = touched.lazy.compactMap { $0 }.first?.persistentStoreCoordinator?.persistentStores ?? []
        if stores.contains(where: isShared) {
            return Set(touched.compactMap { $0 }.filter(isShared).map { $0.identifier ?? anyStore })
        }
        #endif
        return Set(touched.map { $0?.identifier ?? anyStore })
    }

    /// Whether the save in `note` leaves something only CloudKit's own
    /// upload can carry. In the Assistant a new classroom record goes by the
    /// share step (`AssistantShareAttacher`), which puts it into the
    /// classroom share itself and counts it until it's in; only an edit or a
    /// removal of a record already there waits for the upload. Counting new
    /// marks too made the sync line and Leave wait for an upload that had
    /// nothing left to carry, and while iCloud couldn't be reached the line
    /// said "Not sent yet" all morning though every mark had gone (2026-10-22).
    /// The notebook's every change goes by the upload.
    nonisolated static func leavesSomethingToUpload(in note: Notification) -> Bool {
        !storesLeftToUpload(in: note).isEmpty
    }

    /// The stores the save in `note` leaves something to upload from
    /// (`leavesSomethingToUpload`), by identifier.
    nonisolated static func storesLeftToUpload(in note: Notification) -> Set<String> {
        #if ASSISTANT_APP
        let keys = [NSUpdatedObjectsKey, NSDeletedObjectsKey]
        #else
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        #endif
        let changed = keys.flatMap { key in Array((note.userInfo?[key] as? Set<NSManagedObject>) ?? []) }
        return storesToSend(changed)
    }

    /// Returns once CloudKit has exported the saves made so far, or `limit`
    /// has passed.
    func waitUntilSent(upTo limit: Duration) async {
        guard !unsentSinceByStore.isEmpty else { return }
        let sleep = sleep
        let timer = Task { [weak self] in
            try? await sleep(limit)
            self?.settle()
        }
        await withCheckedContinuation { waiters.append($0) }
        timer.cancel()
    }

    private func settle() {
        let resumed = waiters
        waiters = []
        resumed.forEach { $0.resume() }
    }

    private func didLeaveForeground() {
        guard needsKeepAlive else { return }
        SiriSyncKeepAlive.run(named: "Send unsent changes") { [weak self] in
            await self?.sendBeforeSuspending()
        }
    }

    /// What leaving the foreground keeps the app awake for, all within
    /// `limit`: the app's own sending (the Assistant's share attach), then
    /// CloudKit's export of what was saved. The sending is raced against the
    /// limit rather than waited out: `share(_:to:)` can block for good
    /// (`ClassroomShareAttachLock`), and until 2026-10-10 waiting for it held
    /// the app awake past 25 s, up to iOS's own cut-off, which counts against
    /// the app when iOS decides how often to wake it. Only the waiting ends:
    /// an attach still running carries on while the app does, and its marks
    /// stay on the attacher's list for the next try (a save, a return to the
    /// app, the next launch).
    func sendBeforeSuspending(within limit: Duration = UnsentChangesKeepAlive.limit) async {
        let deadline = ContinuousClock.now + limit
        await Self.wait(atMost: limit, sleep: sleep, for: waitForWork)
        await waitUntilSent(upTo: max(.zero, deadline - ContinuousClock.now))
    }

    /// Waits for `work` to return or `limit` to pass, whichever comes first;
    /// true when `work` returned in time. `work` isn't stopped at the limit,
    /// only the wait for it, so the background task around the wait ends on
    /// time. Siri's wait for the share attach uses it too (`SiriHost.didSave`).
    @discardableResult
    static func wait(
        atMost limit: Duration,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        for work: @escaping @Sendable @MainActor () async -> Void
    ) async -> Bool {
        let race = DeadlineRace()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            race.timer = Task {
                try? await sleep(limit)
                guard !Task.isCancelled else { return }
                race.finish(false)
            }
            Task {
                await work()
                race.timer?.cancel()
                race.finish(true)
            }
        }
    }
}

/// One `UnsentChangesKeepAlive.wait(atMost:for:)`: whichever of the work and
/// the timer ends first answers, once.
@MainActor
private final class DeadlineRace {
    var continuation: CheckedContinuation<Bool, Never>?
    var timer: Task<Void, Never>?

    func finish(_ workReturned: Bool) {
        continuation?.resume(returning: workReturned)
        continuation = nil
    }
}
