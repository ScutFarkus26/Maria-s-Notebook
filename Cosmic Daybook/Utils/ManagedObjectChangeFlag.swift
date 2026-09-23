import CoreData
import Foundation
import Synchronization

/// A dirty bit for a result derived from a handful of entities.
///
/// A screen that rebuilds an expensive value on every reload can instead keep
/// the value and rebuild it only when this flag says one of its inputs moved.
/// The flag starts dirty and is set again, synchronously on the posting
/// thread, by anything that could change what a fresh fetch returns:
/// - an edit on `context` (`NSManagedObjectContextObjectsDidChange`);
/// - a save on any context sharing `context`'s store coordinator, including
///   the CloudKit import context (`NSManagedObjectContextDidSave` carries
///   every saved object, registered in `context` or not);
/// - a remote import the history processor reports through
///   `.presentationDataDidChange`;
/// - a context reset (`NSInvalidatedAllObjectsKey`).
///
/// Because delivery is synchronous, a background save has flipped the flag
/// before its `save()` returns, so a reload that follows it always rebuilds.
/// Edits made on `context` earlier in the same run-loop turn have not been
/// announced yet; `consume()` checks the context's pending objects for those.
nonisolated final class ManagedObjectChangeFlag: Sendable {

    let entityNames: Set<String>
    private let dirty: Dirty
    /// Written once in `init`, read once in `deinit`.
    nonisolated(unsafe) private let observers: [NSObjectProtocol]
    private let center: NotificationCenter

    /// The bit itself, shared with the observer blocks so they need not hold `self`.
    private final class Dirty: Sendable {
        let value = Mutex(true)
        func set() { value.withLock { $0 = true } }
    }

    init(entityNames: Set<String>, context: NSManagedObjectContext, center: NotificationCenter = .default) {
        self.entityNames = entityNames
        self.center = center
        let names = entityNames
        let dirty = Dirty()
        self.dirty = dirty
        let objectHandler: @Sendable (Notification) -> Void = { note in
            if !ManagedObjectChangeScope.touched(names, in: note.userInfo).isEmpty { dirty.set() }
        }
        // Saves are watched process-wide but only on this context's store
        // coordinator; another workspace's (or a test's) store cannot move it.
        let coordinatorID = context.persistentStoreCoordinator.map(ObjectIdentifier.init)
        let saveHandler: @Sendable (Notification) -> Void = { note in
            if let coordinatorID,
               let saver = note.object as? NSManagedObjectContext,
               let saverCoordinator = saver.persistentStoreCoordinator,
               ObjectIdentifier(saverCoordinator) != coordinatorID {
                return
            }
            objectHandler(note)
        }
        let key = PersistentHistoryProcessor.changedEntityNamesKey
        observers = [
            center.addObserver(
                forName: .NSManagedObjectContextObjectsDidChange, object: context, queue: nil, using: objectHandler
            ),
            center.addObserver(
                forName: .NSManagedObjectContextDidSave, object: nil, queue: nil, using: saveHandler
            ),
            center.addObserver(forName: .presentationDataDidChange, object: nil, queue: nil) { note in
                guard let changed = note.userInfo?[key] as? Set<String> else { return }
                if !changed.isDisjoint(with: names) { dirty.set() }
            }
        ]
    }

    deinit {
        for token in observers { center.removeObserver(token) }
    }

    /// Whether an input moved since the last `consume()`.
    var isDirty: Bool { dirty.value.withLock { $0 } }

    func markDirty() {
        dirty.set()
    }

    /// Returns whether the derived value must be rebuilt, and clears the flag
    /// so a change that lands during the rebuild sets it again. Also true when
    /// `context` holds unannounced pending edits to a watched entity.
    /// Call on `context`'s queue.
    func consume(pendingIn context: NSManagedObjectContext) -> Bool {
        let wasDirty = dirty.value.withLock { value in
            defer { value = false }
            return value
        }
        return wasDirty || Self.hasPendingChanges(to: entityNames, in: context)
    }

    /// Whether `context`'s inserted, updated or deleted objects include one of
    /// `entityNames`.
    static func hasPendingChanges(to entityNames: Set<String>, in context: NSManagedObjectContext) -> Bool {
        guard context.hasChanges else { return false }
        let pending: [AnyHashable: Any] = [
            NSInsertedObjectsKey: context.insertedObjects,
            NSUpdatedObjectsKey: context.updatedObjects,
            NSDeletedObjectsKey: context.deletedObjects
        ]
        return !ManagedObjectChangeScope.touched(entityNames, in: pending).isEmpty
    }
}
