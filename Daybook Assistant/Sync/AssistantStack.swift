import CoreData

/// The app's one Core Data stack. Siri can run an attendance command with no
/// window open, before `AssistantBootstrapper` has started, and a second
/// `NSPersistentCloudKitContainer` on the same store files would fight the
/// first over sync; so whichever gets here first builds it, and the other
/// gets the same one.
@MainActor
enum AssistantStack {
    private static var stack: CoreDataStack?

    /// What the open stack has saved and not yet sent. Kept here rather than
    /// through `UnsentChangesKeepAlive.install`, so Leave can ask it whether
    /// marks are still on their way (`AssistantBootstrapper.unsentMarks`).
    private(set) static var keepAlive: UnsentChangesKeepAlive?
    /// What the sync line goes by, recorded from launch: Siri's saves too,
    /// with no window open.
    private(set) static var syncRecord: AssistantSyncRecord?

    /// The open stack, if any, without opening one.
    static var current: CoreDataStack? { stack }

    static func shared() throws -> CoreDataStack {
        if let stack { return stack }
        // The launch-argument sample only (Debug). The join screen's sample
        // sits beside this stack instead; see AssistantBootstrapper.
        let made = AssistantSampleClass.isRequested
            ? try AssistantSampleClass.makeStack()
            : try CoreDataStack()
        stack = made
        if !AssistantSampleClass.isRequested {
            // A mark tapped just before the phone locks still goes out. One
            // at a time, as `install` keeps it: a rebuilt stack's replaces
            // the old one's.
            keepAlive = UnsentChangesKeepAlive(
                viewContext: made.viewContext,
                isBusy: { AssistantShareAttacher.shared.isRunning },
                waitForWork: { await AssistantShareAttacher.shared.waitUntilIdle() }
            )
            syncRecord = AssistantSyncRecord(viewContext: made.viewContext)
        }
        return made
    }

    /// Closes the current stack's stores and opens a fresh one on the same
    /// files. For the iCloud account arriving after launch only: a container
    /// that set up without an account can't share records for the rest of
    /// its life. The stores are removed first so two containers never mirror
    /// the same files.
    /// If a store won't come off, the old stack stays (half open, but the
    /// only one) and this throws: a second container on files the first
    /// still holds would fight it over sync. Reopening the app starts clean.
    static func rebuild() throws -> CoreDataStack {
        if let old = stack {
            let coordinator = old.container.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
            stack = nil
        }
        return try shared()
    }

    /// Whether a stack is open: nothing may delete the store files then.
    static var isOpen: Bool { stack != nil }
}
