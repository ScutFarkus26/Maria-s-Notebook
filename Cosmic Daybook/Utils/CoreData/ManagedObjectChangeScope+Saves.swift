import CoreData

extension ManagedObjectChangeScope {
    nonisolated private static let objectSetKeysForSaves: [String] = [
        NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey,
        NSRefreshedObjectsKey, NSInvalidatedObjectsKey
    ]

    /// True when a `NSManagedObjectContextDidSave` payload reports an object of
    /// one of `entityNames`, for a screen narrowing a listener that used to
    /// react to every save.
    ///
    /// Fails open: a payload carrying no object sets at all (an unexpected
    /// shape) or a context reset counts as touching, so nothing the unscoped
    /// listener caught can be lost to a payload this does not recognise.
    /// Reads only `objectID`s, so it is safe on the posting thread.
    nonisolated static func saveTouches(
        _ entityNames: Set<String>,
        in userInfo: [AnyHashable: Any]?
    ) -> Bool {
        guard let userInfo else { return true }
        guard objectSetKeysForSaves.contains(where: { userInfo[$0] != nil }) else { return true }
        return !touched(entityNames, in: userInfo).isEmpty
    }
}
