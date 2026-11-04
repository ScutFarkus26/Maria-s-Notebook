import CoreData
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, #30: the EventKit sync services are process-wide and
/// each read through a graph pointed them at that graph's store, so opening
/// Today in the Sample Class copied the real Calendar (and Reminders, until 2026-11) into the
/// practice store, and EventKit changes kept landing there back in My Class.
/// A Sample Class graph hands out the same services but never moves them.
///
/// Every check runs in one main-actor turn after the reads it checks, so
/// another suite's read can't rebind the shared services in between.
@Suite("Sample Class and the EventKit services (fix 10-17 St)")
@MainActor
struct AppDependenciesFix1017StTests {

    private func sampleDependencies() throws -> AppDependencies {
        AppDependencies(coreDataStack: try CoreDataTestHelpers.makeInMemoryStack(), isSampleClassroom: true)
    }

    @Test("A Sample Class graph never points the sync services at its store")
    func sampleGraphNeverRebinds() throws {
        let primary = try CoreDataTestHelpers.makeDependencies()
        let sample = try sampleDependencies()
        #expect(!primary.isSampleClassroom)
        #expect(sample.isSampleClassroom)

        _ = primary.calendarSync
        // The same objects, so Today's status lines still read the real ones…
        #expect(sample.calendarSync === CalendarSyncService.shared)
        // …still on My Class's store after the Sample Class read them.
        #expect(CalendarSyncService.shared.managedObjectContext === primary.viewContext)
        #expect(CalendarSyncService.shared.managedObjectContext !== sample.viewContext)
    }

    @Test("My Class graphs still bind the services to their store")
    func myClassGraphsStillRebind() throws {
        let sample = try sampleDependencies()
        let primary = try CoreDataTestHelpers.makeDependencies()
        _ = sample.calendarSync
        #expect(primary.calendarSync.managedObjectContext === primary.viewContext)
    }
}
