import CoreData

// The notebook's Schedules booking publisher (plan "Schedules", Phase 1):
// started once per process on the notebook's own stack, at launch, and never
// on the Sample Class, whose stack never comes here.

extension AppBootstrapper {

    /// The one publisher, held for the life of the process.
    @MainActor private static var bookingPublisher: ScheduleBookingPublisher?

    /// Starts the booking publisher on `coreDataStack`'s view context, once.
    /// Not in unit tests, which make their own. It writes only on the lead
    /// guide's devices, in the primary copy of the app, and waits for this
    /// launch to catch up with iCloud before its first run.
    @MainActor
    @discardableResult
    static func startBookingPublisher(on coreDataStack: CoreDataStack) -> ScheduleBookingPublisher? {
        if let bookingPublisher { return bookingPublisher }
        guard !AppBootstrapping.isRunningUnitTests else { return nil }
        let publisher = ScheduleBookingPublisher(
            context: coreDataStack.viewContext, importsExpected: coreDataStack.isCloudKitActive
        )
        let lastImport = caughtUpWithoutImports(syncPreferred: CoreDataStack.syncPreferred(in: .standard))
            ?? ImportWatermark.lastImport(into: .notebook, of: coreDataStack)
        publisher.start(
            launchedAt: ScheduleBookingPublisher.processStartDate() ?? Date(),
            lastImport: lastImport,
            notebookStoreID: coreDataStack.privatePersistentStore?.identifier
        )
        bookingPublisher = publisher
        return publisher
    }
}
