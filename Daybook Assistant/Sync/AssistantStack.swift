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
    /// Whether the classroom share's store may be filed into, from its own
    /// CloudKit events since this stack began opening.
    private(set) static var filingHold: AssistantFilingHold?
    /// Tries the waiting marks when the network comes back or changes.
    private(set) static var networkWatch: AssistantNetworkWatch?

    /// Why her marks mustn't go into the share now, or nil: asked by the
    /// attacher before each pass and before each chunk.
    static var filingStopReason: String? { filingHold?.stopReason }

    /// The open stack, if any, without opening one.
    static var current: CoreDataStack? { stack }

    /// Why `shared()` opened nothing.
    enum OpenError: Error {
        /// A hosted `Daybook Assistant Tests` run: the tests build their own stacks.
        case hostedTestRun
    }

    static func shared() throws -> CoreDataStack {
        if let stack { return stack }
        // A hosted test run never opens this iPhone's own class, as the
        // bootstrapper never starts in one (`AssistantApp`). A test's
        // attendance screen tells Siri its names (`AssistantSiriVocabulary`),
        // and the system then asks the app's entity queries for them, which
        // came here: the simulator's real stores opened, their CloudKit setup
        // failed without an iCloud account, and the filing hold it started
        // stopped every share attacher in the run that reads it, whenever
        // the failure happened to arrive (2026-10-13).
        guard !AssistantBootstrapper.isRunningUnitTests else { throw OpenError.hostedTestRun }
        // The launch-argument sample only (Debug). The join screen's sample
        // sits beside this stack instead; see AssistantBootstrapper.
        let isSample = AssistantSampleClass.isRequested
        // Listening before the stores open, so a setup that fails at once is
        // heard. A failed open drops it with the stack.
        let hold = AssistantFilingHold()
        if !isSample { hold.listen() }
        let made = isSample ? try AssistantSampleClass.makeStack() : try CoreDataStack()
        stack = made
        if !isSample {
            hold.onLift = { AssistantShareAttacher.shared.retryWaiting() }
            filingHold = hold
            let attacher = AssistantShareAttacher.shared
            // A mark tapped just before the phone locks still goes out, and so
            // do marks waiting with a chance of going (offline, or rested):
            // locking tries them. One at a time, as `install` keeps it: a
            // rebuilt stack's replaces the old one's.
            keepAlive = UnsentChangesKeepAlive(
                viewContext: made.viewContext,
                isBusy: { attacher.isRunning },
                hasWaitingWork: { attacher.pendingCount > 0 && (attacher.isOffline || attacher.backlogIsDue()) },
                waitForWork: {
                    attacher.retryWaiting()
                    await attacher.waitUntilIdle()
                }
            )
            let record = AssistantSyncRecord(viewContext: made.viewContext)
            // A successful sync proves iCloud can be reached.
            record.onSharedStoreSynced = { if attacher.isOffline { attacher.retryWaiting() } }
            syncRecord = record
            networkWatch?.stop()
            networkWatch = .live { attacher.retryWaiting() }
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
