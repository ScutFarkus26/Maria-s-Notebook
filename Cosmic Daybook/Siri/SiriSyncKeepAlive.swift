//
//  SiriSyncKeepAlive.swift
//  Cosmic Daybook
//
//  Siri runs an attendance intent without opening the app, and iOS suspends
//  the app soon after the intent answers. A mark saved just before that would
//  sit on the phone until the next launch; these keep the process awake long
//  enough for it to reach iCloud (and, in Daybook Assistant, the classroom
//  share), and let Siri answer straight away.
//
//  Shared with Daybook Assistant, which compiles this file by path. It stays
//  on the classic `eventChangedNotification`: the Assistant supports iOS 18.
//

import CoreData
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum SiriSyncKeepAlive {
    /// Runs `work` under a background-task assertion on iOS, so a suspended
    /// app finishes it; elsewhere it simply runs.
    static func run(named name: String = "Siri attendance sync", _ work: @escaping @MainActor () async -> Void) {
        #if canImport(UIKit)
        let token = BackgroundTaskToken()
        token.id = UIApplication.shared.beginBackgroundTask(withName: name) {
            token.end()
        }
        Task {
            await work()
            token.end()
        }
        #else
        Task { await work() }
        #endif
    }

    #if canImport(UIKit)
    private final class BackgroundTaskToken {
        var id: UIBackgroundTaskIdentifier = .invalid

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
    #endif
}

/// Waits for the next CloudKit export to go up (`ends`), or a time limit. Created
/// before the save it follows, so an export that finishes quickly is caught;
/// an export that started earlier doesn't hold that save, so it doesn't count.
/// In the notebook it must also be an export of a store that save wrote to:
/// any store's export ended the wait, so the private store's could end it
/// while the classroom share's, holding a co-teacher's marks, was still to go
/// (bug hunt 2026-11-02, #25). The save is the first one on the main thread
/// after the watch is made: Siri's commit makes it and saves straight after,
/// with nothing in between.
@MainActor
final class SiriExportWatch {
    private var observer: (any NSObjectProtocol)?
    private var saveObserver: (any NSObjectProtocol)?
    private var finished = false
    private var continuation: CheckedContinuation<Void, Never>?
    /// The stores the watched save wrote to, by identifier; nil until it has saved.
    private(set) var savedStores: Set<String>?

    init() {
        let created = Date()
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: nil, queue: nil
        ) { [weak self] note in
            guard Thread.isMainThread else { return }
            let stores = Set(UnsentChangesKeepAlive.changedObjects(in: note).map {
                $0.objectID.persistentStore?.identifier ?? UnsentChangesKeepAlive.anyStore
            })
            MainActor.assumeIsolated { self?.noteSave(stores) }
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            guard let event else { return }
            let container = note.object as? NSPersistentCloudKitContainer
            let configuration = container?.persistentStoreCoordinator.persistentStores
                .first { $0.identifier == event.storeIdentifier }?.configurationName
            let type = event.type, ended = event.endDate != nil, succeeded = event.succeeded
            let startedSinceWatching = event.startDate >= created, store = event.storeIdentifier
            MainActor.assumeIsolated {
                guard let self, Self.ends(
                    type: type, ended: ended, succeeded: succeeded,
                    startedSinceWatching: startedSinceWatching, storeConfiguration: configuration,
                    storeIdentifier: store, savedStores: self.savedStores
                ) else { return }
                self.stop()
            }
        }
    }

    /// The watched save: its stores are what an export must be of.
    private func noteSave(_ stores: Set<String>) {
        guard savedStores == nil else { return }
        savedStores = stores
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
            self.saveObserver = nil
        }
    }

    /// Whether a CloudKit event ends the wait: an export that started after
    /// the watch began and went up. A failed one (offline, a quota, a
    /// conflict) keeps it waiting, since the marks are still on the phone.
    /// In the Assistant it must also be the shared store's: her marks go to
    /// the classroom share, and her private store's export says nothing about
    /// them. In the notebook it must be of a store the save wrote to
    /// (`savedStores`; any store before the save is known). Pure, for the tests.
    nonisolated static func ends(
        type: NSPersistentCloudKitContainer.EventType,
        ended: Bool,
        succeeded: Bool,
        startedSinceWatching: Bool,
        storeConfiguration: String?,
        storeIdentifier: String? = nil,
        savedStores: Set<String>? = nil
    ) -> Bool {
        guard type == .export, ended, succeeded, startedSinceWatching else { return false }
        #if ASSISTANT_APP
        return storeConfiguration == CoreDataStack.sharedConfiguration
        #else
        guard let savedStores, let storeIdentifier,
              !savedStores.contains(UnsentChangesKeepAlive.anyStore) else { return true }
        return savedStores.contains(storeIdentifier)
        #endif
    }

    func wait(upTo limit: Duration) async {
        guard !finished else { return }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: limit)
            self?.stop()
        }
        await withCheckedContinuation { continuation = $0 }
        timer.cancel()
    }

    /// Ends the wait (or stops watching before one starts).
    func stop() {
        finished = true
        for token in [observer, saveObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(token)
        }
        observer = nil
        saveObserver = nil
        continuation?.resume()
        continuation = nil
    }
}
