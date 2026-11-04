import Testing
@testable import CosmicDaybook

// MARK: - One live instance per service
//
// `AppDependencies` hands out the process-wide EventKit sync services and the
// toast service rather than building copies of its own. `CalendarSyncService`
// once had two: the container built one while the Today card watched
// `.shared`, so the card could observe an object that was not the one
// syncing, and two `EKEventStore` observers ran. These tests pin the rule:
// each accessor returns the same object on every read, from every container,
// and the sync services come back bound to the reading container's store.
// Nothing here constructs a service — `CalendarSyncService.init` touches
// `EKEventStore` — identity is asserted through the container alone.

@Suite("AppDependencies single instances")
@MainActor
struct AppDependenciesSingleInstanceTests {

    @Test("calendarSync is one object, the process-wide instance, bound to the store")
    func calendarSyncIsSingleInstance() throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        #expect(dependencies.calendarSync === dependencies.calendarSync)
        // The Today views read `dependencies.calendarSync`; the syncing object is `.shared`.
        #expect(dependencies.calendarSync === CalendarSyncService.shared)
        #expect(dependencies.calendarSync.managedObjectContext === dependencies.viewContext)
    }

    @Test("toastService is one object, the process-wide instance")
    func toastServiceIsSingleInstance() throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        #expect(dependencies.toastService === dependencies.toastService)
        #expect(dependencies.toastService === ToastService.shared)
    }

    @Test("Two containers share the sync services and each read rebinds the store")
    func containersShareSyncServicesAndRebind() throws {
        let first = try CoreDataTestHelpers.makeDependencies()
        let second = try CoreDataTestHelpers.makeDependencies()
        #expect(first.calendarSync === second.calendarSync)

        #expect(second.calendarSync.managedObjectContext === second.viewContext)
        #expect(first.calendarSync.managedObjectContext === first.viewContext)
    }
}
