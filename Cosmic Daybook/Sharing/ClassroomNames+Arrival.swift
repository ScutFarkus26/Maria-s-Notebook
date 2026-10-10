// ClassroomNames+Arrival.swift
// Whose classroom the names belong to, and when it is on this device, so
// `ClassroomNames.writeWaitingName` may write a waiting name or fold this
// person's duplicate rows.

import CoreData
import Foundation

extension ClassroomNames {

    /// The classroom owner's record name: the one this device's membership
    /// row names (an assistant's, written when she joined), else, on the
    /// guide's own devices, this account's (his row names the owner with
    /// CloudKit's stand-in). Nil when not known.
    static func ownerRecordName(in context: NSManagedObjectContext) -> String? {
        let membership = CDClassroomMembership.current(in: context)
        if let owner = ClassroomIdentity.realRecordName(membership?.ownerIdentity) { return owner }
        #if ASSISTANT_APP
        return nil
        #else
        guard (membership?.role ?? .leadGuide) == .leadGuide else { return nil }
        return ClassroomIdentity.currentUserRecordName
        #endif
    }

    /// Turns the rows `context` holds unchanged back into faults, so they are
    /// read as the store holds them now, not as kept from before an import
    /// the context hasn't merged yet: a fold run as an import finishes must
    /// carry the rename that import brought. Rows with unsaved changes stay.
    static func refreshUnchangedRows(in context: NSManagedObjectContext) {
        for case let row as CDClassroomPerson in context.registeredObjects where !row.hasChanges {
            context.refresh(row, mergeChanges: false)
        }
    }

    /// Whether the classroom has arrived on this device this launch, and the
    /// one name write waiting for it.
    ///
    /// The launch's fold ran before that launch's sync, so an older name could
    /// go up over a rename still on its way down; and her row was written at
    /// launch before she was in any class (2026-10-05 sync and sharing hunt).
    /// So `writeWaitingName` does nothing until `classIsHere`, and then runs
    /// again after the next successful import (`holdUntilNextImport`).
    ///
    /// Imports are noted from CloudKit's events, in memory, for this launch
    /// only. The Daybook Assistant compiles this file and targets iOS 18, so
    /// it follows the classic `eventChangedNotification`, not the typed
    /// messages. The notebook starts it as soon as its stores open
    /// (`AppBootstrapping.startStoreObservers`), before the launch import
    /// finishes, which it used to miss (2026-10-09 hunt, #4); the Assistant
    /// from `ClassroomIdentity.refreshRecordName()`. An import that finished
    /// before then is missed, and the write waits for the next one.
    final class Arrival {

        /// The app's. Unit tests have no CloudKit and no imports, so there it
        /// lets every write through at once, as before it existed; tests of
        /// the waiting make their own.
        static let shared = Arrival(
            waitsForTheClass: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        )

        /// False: every write goes through at once (unit tests).
        let waitsForTheClass: Bool
        /// When each store's latest successful import this launch began, by
        /// `NSPersistentStore.identifier`.
        private(set) var importStarts: [String: Date] = [:]
        /// The write waiting for the next import, and the record name it was
        /// held for. One at a time: a later one does the same work.
        private var held: (recordName: String, write: () async -> Void)?
        /// The view context whose name rows' zones each import warms
        /// (`ClassroomNames.warmZones`, which sets it).
        weak var zonesContext: NSManagedObjectContext?
        /// What the latest import started, after any earlier import's: warming
        /// the zones, then the held write. Kept so tests can wait for it.
        private(set) var importWork: Task<Void, Never>?
        /// A warm-up is in `importWork` and hasn't begun: a later import needs
        /// no second one, which would only wait behind it for the gate.
        private var warmUpQueued = false
        /// Set once by `start()`, on the main actor; removed in `deinit`.
        private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

        init(waitsForTheClass: Bool = true) {
            self.waitsForTheClass = waitsForTheClass
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        /// Starts noting CloudKit's successful imports, once. Never when it
        /// doesn't wait.
        func start() {
            guard waitsForTheClass, observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                      event.type == .import, event.succeeded, event.endDate != nil else { return }
                let store = event.storeIdentifier
                let started = event.startDate
                MainActor.assumeIsolated {
                    self?.noteImport(intoStoreWithIdentifier: store, startedAt: started)
                }
            }
        }

        /// An import into the store `storeIdentifier`, begun at `start`,
        /// finished successfully: note it, warm the name rows' zones when it
        /// brought rows the reads haven't placed, and run the write waiting
        /// for one, unless the account changed since it was held (the caller
        /// writes again once it has read the new one). Both wait for CloudKit
        /// off the main thread, in `importWork`.
        ///
        /// Every iCloud download used to queue a warm-up behind the gate, so a
        /// name saved on a busy morning waited behind all of them (2026-10-09
        /// hunt, #6). Now one is queued only for new name rows, and never a
        /// second while one waits to begin; it checks again when it begins,
        /// since a write's lookup may have placed them meanwhile.
        func noteImport(intoStoreWithIdentifier storeIdentifier: String, startedAt start: Date) {
            if importStarts[storeIdentifier].map({ start > $0 }) ?? true { importStarts[storeIdentifier] = start }
            let write = held.flatMap { ClassroomIdentity.currentUserRecordName == $0.recordName ? $0.write : nil }
            held = nil
            let context = zonesContext
            let warms = !warmUpQueued && context.map(ClassroomNames.hasRowsWithoutZones(in:)) == true
            guard write != nil || warms else { return }
            if warms { warmUpQueued = true }
            let earlier = importWork
            importWork = Task {
                await earlier?.value
                if warms, let context {
                    warmUpQueued = false
                    if ClassroomNames.hasRowsWithoutZones(in: context) {
                        await ClassroomNames.warmZones(in: context, arrival: nil)
                    }
                }
                await write?()
            }
        }

        /// Runs `write` after the next successful import, for `recordName`.
        /// Never when it doesn't wait: then nothing is ever held back.
        func holdUntilNextImport(for recordName: String, _ write: @escaping () async -> Void) {
            guard waitsForTheClass else { return }
            held = (recordName, write)
        }

        /// Whether the class is on this device, so a `role`'s name may be
        /// written and their rows folded: a classroom membership is pinned,
        /// the notebook's first download from iCloud is done
        /// (`FirstDownloadGate`), this is the copy of the app that may file
        /// and fold (`CoreDataStack.isSecondaryProcess`, on the Mac), and an
        /// import into the store `role`'s rows live in has finished this
        /// launch, one that began after the membership was pinned (after she
        /// joined, the one that brought the class down). With one store
        /// (no CloudKit) nothing is waited for but the membership.
        func classIsHere(role: CDClassroomMembership.ClassroomRole, in context: NSManagedObjectContext) -> Bool {
            guard waitsForTheClass else { return true }
            guard let membership = CDClassroomMembership.current(in: context),
                  !membership.classroomZoneID.isEmpty else { return false }
            #if !ASSISTANT_APP
            // The Assistant arms this gate on a fresh install but never opens
            // it (only the notebook's sync service does), so there it would
            // hold her name back for good; the import check below covers her.
            guard !FirstDownloadGate.isPending(), !CoreDataStack.isSecondaryProcess else { return false }
            #endif
            guard let store = RestockService.destinationStore(for: role, in: context) else { return true }
            guard let started = importStarts[store.identifier ?? ""] else { return false }
            return started >= (membership.modifiedAt ?? membership.joinedAt ?? .distantPast)
        }
    }
}
