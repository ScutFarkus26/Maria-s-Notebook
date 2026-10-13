import CoreData

// The notebook's ParentLocker sync (plan "ParentLocker attendance", Phase 3):
// started once per process on the notebook's own stack, at launch or by the
// Shortcuts action when it launches the app, and never on the Sample Class,
// whose stack never comes here.

extension AppBootstrapper {

    /// The one sync, held here: `ParentLockerSync.current` is weak.
    @MainActor private static var parentLockerSync: ParentLockerSync?

    /// Starts the ParentLocker sync on `coreDataStack`'s view context, once.
    /// Not in unit tests, which make their own. Returns the running sync.
    @MainActor
    @discardableResult
    static func startParentLockerSync(on coreDataStack: CoreDataStack) -> ParentLockerSync? {
        if let parentLockerSync { return parentLockerSync }
        guard !AppBootstrapping.isRunningUnitTests else { return nil }
        let context = coreDataStack.viewContext
        let sync = ParentLockerSync(context: context, importsExpected: coreDataStack.isCloudKitActive)
        sync.start(watching: context)
        parentLockerSync = sync
        return sync
    }
}
