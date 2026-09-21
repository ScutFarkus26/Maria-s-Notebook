import Combine
import CoreData
import SwiftUI

/// Which of a watched entity set a Core Data change notification touched.
///
/// Reads the object sets an `NSManagedObjectContextObjectsDidChange` or
/// `NSManagedObjectContextDidSave` notification carries — only the objects
/// that changed, never a table — so a screen can learn that something it
/// shows moved without keeping every row of it registered. A context reset
/// (`NSInvalidatedAllObjectsKey`) counts as touching everything watched.
enum ManagedObjectChangeScope {
    nonisolated private static let objectSetKeys: [String] = [
        NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey,
        NSRefreshedObjectsKey, NSInvalidatedObjectsKey
    ]

    /// The members of `entityNames` that `userInfo` reports an object of.
    /// Reads only `objectID`s, which are safe from any thread.
    nonisolated static func touched(
        _ entityNames: Set<String>,
        in userInfo: [AnyHashable: Any]?
    ) -> Set<String> {
        guard let userInfo else { return [] }
        if userInfo[NSInvalidatedAllObjectsKey] != nil { return entityNames }
        var touched: Set<String> = []
        for key in objectSetKeys {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            for object in objects {
                guard let name = object.objectID.entity.name, entityNames.contains(name) else { continue }
                touched.insert(name)
                if touched.count == entityNames.count { return touched }
            }
        }
        return touched
    }
}

extension View {
    /// Runs `action` with the touched subset of `entityNames` whenever one of
    /// them changes anywhere this screen could see it:
    /// - an edit on `context` — saved or not, the same moment a `@FetchRequest`
    ///   on that context would have reacted;
    /// - a save on any other context in the process, which reaches `context`
    ///   only for objects it has registered, so is watched at the source;
    /// - a remote import the history processor reports through
    ///   `.presentationDataDidChange`.
    ///
    /// `entityNames` must be a subset of
    /// `PersistentHistoryProcessor.presentationEntityNames`; the remote signal
    /// covers nothing else. Every path delivers on the main queue.
    func onPresentationDataChange(
        of entityNames: Set<String>,
        in context: NSManagedObjectContext,
        perform action: @escaping (Set<String>) -> Void
    ) -> some View {
        assert(
            entityNames.isSubset(of: PersistentHistoryProcessor.presentationEntityNames),
            "onPresentationDataChange watches only the entities the history processor reports"
        )
        let center = NotificationCenter.default
        let contextID = ObjectIdentifier(context)
        let key = PersistentHistoryProcessor.changedEntityNamesKey
        return self
            .onReceive(
                center.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
                    .compactMap { note -> Set<String>? in
                        let touched = ManagedObjectChangeScope.touched(entityNames, in: note.userInfo)
                        return touched.isEmpty ? nil : touched
                    }
                    .receive(on: DispatchQueue.main),
                perform: action
            )
            .onReceive(
                center.publisher(for: .NSManagedObjectContextDidSave)
                    .compactMap { note -> Set<String>? in
                        // The view context's own saves were already seen as edits above.
                        guard let saved = note.object as AnyObject?, ObjectIdentifier(saved) != contextID else {
                            return nil
                        }
                        let touched = ManagedObjectChangeScope.touched(entityNames, in: note.userInfo)
                        return touched.isEmpty ? nil : touched
                    }
                    .receive(on: DispatchQueue.main),
                perform: action
            )
            .onReceive(
                center.publisher(for: .presentationDataDidChange)
                    .compactMap { note -> Set<String>? in
                        guard let changed = note.userInfo?[key] as? Set<String> else { return nil }
                        let touched = changed.intersection(entityNames)
                        return touched.isEmpty ? nil : touched
                    }
                    .receive(on: DispatchQueue.main),
                perform: action
            )
    }
}
