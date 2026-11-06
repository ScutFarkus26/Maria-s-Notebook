import Foundation
import CoreData
import Synchronization
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// What `ParentLockerSync` follows while the app runs, each on a classic
/// notification (the Daybook Assistant targets iOS 18, so no typed Core Data
/// messages here; CLOUDKIT_GUIDE, Monitoring):
/// - **Saves of attendance records** on the context's store coordinator, from
///   any context: this device's own (taps, Siri, MCP, undo) and the CloudKit
///   import's, told apart by the saving context's transaction author. Only
///   object IDs leave the posting thread; the sync reads the records on the
///   main actor, and only when they're today's. Never the duplicate
///   cleanup's merges: they're no change made here (bug hunt 2026-11-05 #20).
/// - **The day's send record synced in**, while signed in, and **the
///   guide's settings** changed: a day sent elsewhere releases this device's
///   own changes from before "after", and the line follows the day, a switch
///   to email included (bug hunt 2026-11-05 #11, #15; `dayRecordsChanged`).
/// - **CloudKit imports that finish**, which release the catch-up.
/// - **The app coming back** to the front, and on the Mac going away, so a
///   switch between apps doesn't count as a return (`appBecameActive`).
/// - **A new day** (`.NSCalendarDayChanged`), so yesterday's work goes and
///   the line moves on even on a Mac left open all night (`dayChanged`).
///
/// Nothing polls. Every observer goes when the watcher does.
@MainActor
final class ParentLockerWatcher {

    /// Written once in `init`, read once in `deinit`.
    nonisolated(unsafe) private let tokens: [any NSObjectProtocol]
    private let center: NotificationCenter
    /// Whether the sync is signed in, as the save observer reads it on the
    /// posting thread: signed out, the sync notes no change, so a save
    /// doesn't hop to the main actor for nothing (bug hunt 2026-11-03 #21).
    private let signedIn: SignedIn

    /// Whether saves are followed; the sync sets it as its sign-in changes.
    var followsSaves: Bool {
        get { signedIn.value }
        set { signedIn.value = newValue }
    }

    init(context: NSManagedObjectContext, sync: ParentLockerSync, center: NotificationCenter = .default) {
        self.center = center
        let signedIn = SignedIn(sync.isSignedIn)
        self.signedIn = signedIn
        let coordinatorID = context.persistentStoreCoordinator.map(ObjectIdentifier.init)
        let storeIDs = Set(context.persistentStoreCoordinator?.persistentStores.compactMap(\.identifier) ?? [])
        var tokens = [
            center.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: nil) { [weak sync] note in
                guard let sync else { return }
                let followed = signedIn.value
                let saved = followed ? Self.attendanceSave(note, coordinatorID: coordinatorID) : nil
                let dayRecords = Self.changesDayRecords(note, coordinatorID: coordinatorID, signedIn: followed)
                guard saved != nil || dayRecords else { return }
                Task { @MainActor in
                    if let saved { sync.recordsSaved(saved.records, imported: saved.imported) }
                    if dayRecords { sync.dayRecordsChanged() }
                }
            },
            center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
            ) { [weak sync] note in
                guard let sync, Self.isFinishedImport(note, storeIDs: storeIDs) else { return }
                Task { @MainActor in sync.importFinished() }
            }
        ]
        tokens.append(center.addObserver(forName: Self.becameActive, object: nil, queue: .main) { [weak sync] _ in
            MainActor.assumeIsolated { sync?.appBecameActive() }
        })
        tokens.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak sync] _ in
            MainActor.assumeIsolated { sync?.dayChanged() }
        })
        #if canImport(AppKit) && !canImport(UIKit)
        tokens.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak sync] _ in
            MainActor.assumeIsolated { sync?.appResigned() }
        })
        #endif
        self.tokens = tokens
    }

    deinit {
        for token in tokens { center.removeObserver(token) }
    }

    /// A flag read on any thread.
    nonisolated final class SignedIn: Sendable {
        private let flag: Mutex<Bool>

        init(_ value: Bool) { flag = Mutex(value) }

        var value: Bool {
            get { flag.withLock { $0 } }
            set { flag.withLock { $0 = newValue } }
        }
    }

    private static var becameActive: Notification.Name {
        #if canImport(UIKit)
        UIApplication.didBecomeActiveNotification
        #else
        NSApplication.didBecomeActiveNotification
        #endif
    }

    /// The attendance records a save inserted or changed, and whether the
    /// CloudKit import made it; nil for a save of nothing of attendance, or
    /// on another stack (the Sample Class's, a test's). Runs on the posting
    /// thread, which is the saving context's own queue, and reads only object
    /// IDs there.
    nonisolated static func attendanceSave(
        _ note: Notification, coordinatorID: ObjectIdentifier?
    ) -> (records: [NSManagedObjectID], imported: Bool)? {
        guard let saver = saver(of: note, coordinatorID: coordinatorID) else { return nil }
        let records = changedIDs(note).filter { $0.entity.name == attendanceEntity }
        guard !records.isEmpty else { return nil }
        return (records, isImport(author: saver.transactionAuthor))
    }

    /// Whether a save changed the day's send record, synced in from another
    /// device while signed in, or the guide's settings, from anywhere. Runs
    /// on the posting thread, as `attendanceSave` does.
    nonisolated static func changesDayRecords(
        _ note: Notification, coordinatorID: ObjectIdentifier?, signedIn: Bool
    ) -> Bool {
        guard let saver = saver(of: note, coordinatorID: coordinatorID) else { return false }
        let entities = Set(changedIDs(note).compactMap(\.entity.name))
        if entities.contains(settingsEntity) { return true }
        return signedIn && entities.contains(sendEntity) && isImport(author: saver.transactionAuthor)
    }

    /// The context that saved, when it's on this stack (any, without
    /// `coordinatorID`), and not the duplicate cleanup's.
    nonisolated private static func saver(
        of note: Notification, coordinatorID: ObjectIdentifier?
    ) -> NSManagedObjectContext? {
        guard let saver = note.object as? NSManagedObjectContext,
              saver.name != duplicateCleanupContextName else { return nil }
        if let coordinatorID {
            guard let coordinator = saver.persistentStoreCoordinator,
                  ObjectIdentifier(coordinator) == coordinatorID else { return nil }
        }
        return saver
    }

    /// The IDs of the objects a save inserted or changed.
    nonisolated private static func changedIDs(_ note: Notification) -> [NSManagedObjectID] {
        [NSInsertedObjectsKey, NSUpdatedObjectsKey].flatMap { key in
            (note.userInfo?[key] as? Set<NSManagedObject>)?.map(\.objectID) ?? []
        }
    }

    nonisolated static let attendanceEntity = "AttendanceRecord"
    /// The day's sends of attendance (`CDAttendanceEmailSend`) and the
    /// guide's settings they're written from (`CDAttendanceEmailSettings`).
    nonisolated static let sendEntity = "AttendanceEmailSend"
    nonisolated static let settingsEntity = "AttendanceEmailSettings"

    /// The name `DeduplicationCoordinator` gives its context
    /// (`DeduplicationCoordinator.contextName`, which the Daybook Assistant
    /// doesn't compile; a test pins the two equal).
    nonisolated static let duplicateCleanupContextName = "Duplicate cleanup"

    /// Whether a save's author is CloudKit's import
    /// ("NSCloudKitMirroringDelegate.import"). The app's own contexts carry
    /// its author (`PersistentHistoryProcessor.transactionAuthor`); one that
    /// carries none is the app's too.
    nonisolated static func isImport(author: String?) -> Bool {
        author?.hasPrefix("NSCloudKitMirroringDelegate") ?? false
    }

    /// Whether a CloudKit event is an import into one of `storeIDs` that
    /// finished and worked.
    nonisolated static func isFinishedImport(_ note: Notification, storeIDs: Set<String>) -> Bool {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return false }
        return event.type == .import && event.endDate != nil && event.succeeded
            && (storeIDs.isEmpty || storeIDs.contains(event.storeIdentifier))
    }
}
