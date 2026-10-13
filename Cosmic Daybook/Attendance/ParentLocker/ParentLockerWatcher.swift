import Foundation
import CoreData
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
///   main actor, and only when they're today's.
/// - **CloudKit imports that finish**, which release the catch-up.
/// - **The app coming back** to the front, and on the Mac going away, so a
///   switch between apps doesn't count as a return (`appBecameActive`).
///
/// Nothing polls. Every observer goes when the watcher does.
@MainActor
final class ParentLockerWatcher {

    /// Written once in `init`, read once in `deinit`.
    nonisolated(unsafe) private let tokens: [any NSObjectProtocol]
    private let center: NotificationCenter

    init(context: NSManagedObjectContext, sync: ParentLockerSync, center: NotificationCenter = .default) {
        self.center = center
        let coordinatorID = context.persistentStoreCoordinator.map(ObjectIdentifier.init)
        let storeIDs = Set(context.persistentStoreCoordinator?.persistentStores.compactMap(\.identifier) ?? [])
        var tokens = [
            center.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: nil) { [weak sync] note in
                guard let sync, let saved = Self.attendanceSave(note, coordinatorID: coordinatorID) else { return }
                Task { @MainActor in sync.recordsSaved(saved.records, imported: saved.imported) }
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
        guard let saver = note.object as? NSManagedObjectContext else { return nil }
        if let coordinatorID {
            guard let coordinator = saver.persistentStoreCoordinator,
                  ObjectIdentifier(coordinator) == coordinatorID else { return nil }
        }
        var records: [NSManagedObjectID] = []
        for key in [NSInsertedObjectsKey, NSUpdatedObjectsKey] {
            guard let objects = note.userInfo?[key] as? Set<NSManagedObject> else { continue }
            for object in objects where object.objectID.entity.name == attendanceEntity {
                records.append(object.objectID)
            }
        }
        guard !records.isEmpty else { return nil }
        return (records, isImport(author: saver.transactionAuthor))
    }

    nonisolated static let attendanceEntity = "AttendanceRecord"

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
