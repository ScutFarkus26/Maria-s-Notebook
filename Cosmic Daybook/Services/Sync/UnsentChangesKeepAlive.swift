//
//  UnsentChangesKeepAlive.swift
//  Cosmic Daybook
//
//  iOS suspends an app a few seconds after it leaves the foreground. A mark
//  tapped just before the phone is locked would then sit on the device until
//  the next launch or a background wake, and the other devices wouldn't see
//  it. This keeps the app awake after it leaves, until CloudKit has exported
//  what was saved (at most 25 s), and only when something is waiting to go.
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

    private static var installed: UnsentChangesKeepAlive?

    /// When the view context last saved changes no finished export has
    /// covered yet: an export counts only if it started after the save.
    private(set) var unsentSince: Date?
    private let isBusy: @MainActor () -> Bool
    private let waitForWork: @MainActor () async -> Void
    /// Written in `init` only; read again in `deinit`.
    private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Watches `stack` from now on, replacing whatever was watched before.
    /// `isBusy` and `waitForWork` add the app's own sending (the Assistant's
    /// share attach) to what leaving the foreground waits for.
    static func install(
        for stack: CoreDataStack,
        isBusy: @escaping @MainActor () -> Bool = { false },
        waitForWork: @escaping @MainActor () async -> Void = {}
    ) {
        installed = UnsentChangesKeepAlive(
            viewContext: stack.viewContext, isBusy: isBusy, waitForWork: waitForWork
        )
    }

    init(
        viewContext: NSManagedObjectContext,
        isBusy: @escaping @MainActor () -> Bool = { false },
        waitForWork: @escaping @MainActor () async -> Void = {}
    ) {
        self.isBusy = isBusy
        self.waitForWork = waitForWork
        let center = NotificationCenter.default
        // Delivered on the saving thread (the main one, for the view
        // context), so the time is noted before any export can start.
        observers.append(center.addObserver(
            forName: .NSManagedObjectContextDidSave, object: viewContext, queue: nil
        ) { [weak self] note in
            let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
            let changed = keys.contains { !((note.userInfo?[$0] as? Set<NSManagedObject>)?.isEmpty ?? true) }
            guard changed else { return }
            let now = Date()
            MainActor.assumeIsolated { self?.saved(at: now) }
        })
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .export, event.succeeded, event.endDate != nil else { return }
            let started = event.startDate
            MainActor.assumeIsolated { self?.exported(startedAt: started) }
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
    var hasUnsentWork: Bool { unsentSince != nil || isBusy() }

    func saved(at date: Date) {
        if unsentSince == nil { unsentSince = date }
    }

    func exported(startedAt start: Date) {
        guard let since = unsentSince, start >= since else { return }
        unsentSince = nil
        settle()
    }

    /// Returns once CloudKit has exported the saves made so far, or `limit`
    /// has passed.
    func waitUntilSent(upTo limit: Duration) async {
        guard unsentSince != nil else { return }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: limit)
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
        guard hasUnsentWork else { return }
        SiriSyncKeepAlive.run(named: "Send unsent changes") { [weak self] in
            guard let self else { return }
            let deadline = ContinuousClock.now + Self.limit
            await waitForWork()
            await waitUntilSent(upTo: max(.zero, deadline - ContinuousClock.now))
        }
    }
}
