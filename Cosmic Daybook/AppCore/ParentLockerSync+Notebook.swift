import CoreData

// Which ParentLocker sync a notebook screen talks to (plan "ParentLocker
// attendance", Phase 3).

extension ParentLockerSync {

    /// The running sync, when it follows `context`'s class: nil in the Sample
    /// Class (its own store), so nothing there reaches the real ParentLocker.
    static func current(for context: NSManagedObjectContext) -> ParentLockerSync? {
        guard let sync = current, (sync.store as? ParentLockerCoreDataStore)?.context === context else { return nil }
        return sync
    }
}
