import CoreData
import Foundation
import Synchronization

/// Records every save made through one persistent store coordinator until
/// `finish()`: whether it ran on the main thread, which context made it, and
/// which entities it wrote.
///
/// `NSManagedObjectContextDidSave` is posted synchronously on the saving
/// context's own queue, so `Thread.isMainThread` inside the observer says
/// where the save, and the work that led up to it, ran.
@MainActor
final class ContextSaveRecorder {
    nonisolated struct Save: Sendable {
        let onMainThread: Bool
        let context: ObjectIdentifier
        let entityNames: Set<String>
    }

    private let log = ContextSaveLog()
    private var token: (any NSObjectProtocol)?

    init(coordinator: NSPersistentStoreCoordinator?) {
        let log = log
        token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: nil, queue: nil
        ) { [weak coordinator] note in
            // Other suites save in parallel; keep only this store's saves.
            guard let coordinator,
                  let context = note.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === coordinator else { return }
            log.record(note, from: context)
        }
    }

    /// Stops recording and returns the saves in the order they happened.
    func finish() -> [Save] {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        return log.saves
    }
}

private nonisolated final class ContextSaveLog: Sendable {
    private let entries = Mutex<[ContextSaveRecorder.Save]>([])

    var saves: [ContextSaveRecorder.Save] {
        entries.withLock { $0 }
    }

    /// Runs on the saving context's queue; reads only object IDs.
    func record(_ note: Notification, from context: NSManagedObjectContext) {
        var names: Set<String> = []
        for key in [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey] {
            for object in (note.userInfo?[key] as? Set<NSManagedObject>) ?? [] {
                if let name = object.objectID.entity.name { names.insert(name) }
            }
        }
        let save = ContextSaveRecorder.Save(
            onMainThread: Thread.isMainThread, context: ObjectIdentifier(context), entityNames: names
        )
        entries.withLock { $0.append(save) }
    }
}
