import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

// schedule_for_range printed four "Untitled work — unassigned" check-ins on
// 2026-09-09. A check-in is keyed by a workID string and a work relationship,
// and five creation paths wrote only the string. These pin down the three
// rules that close that: creation writes both, launch relinks what was left
// behind, and deleting a work takes its check-ins with it either way.

@Suite("Work Check-In Integrity")
@MainActor
struct WorkCheckInIntegrityTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func checkIns(in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        context.safeFetch(CDFetchRequest(CDWorkCheckIn.self))
    }

    /// The legacy shape: a check-in that names its work by string only.
    @discardableResult
    private func seedStringOnlyCheckIn(
        workID: String, on date: Date, in context: NSManagedObjectContext
    ) -> CDWorkCheckIn {
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.workID = workID
        checkIn.date = date
        checkIn.purpose = "progressCheck"
        return checkIn
    }

    @Test("The factory writes the workID string and the relationship together")
    func factoryLinksBothWays() throws {
        let context = try makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes")
        let checkIn = CDWorkCheckIn.make(for: work, on: Date(), purpose: " progressCheck ", in: context)

        #expect(checkIn.work === work)
        #expect(checkIn.workID == work.id?.uuidString)
        #expect(checkIn.purpose == "progressCheck")
        #expect(checkIn.resolvedWork() === work)
    }

    @Test("resolvedWork follows the string when the relationship was never set")
    func resolvedWorkFallsBackToString() throws {
        let context = try makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes")
        CoreDataTestHelpers.save(context)
        let checkIn = seedStringOnlyCheckIn(workID: try #require(work.id?.uuidString), on: Date(), in: context)

        #expect(checkIn.work == nil)
        #expect(checkIn.resolvedWork(in: context) === work)
        #expect(seedStringOnlyCheckIn(workID: UUID().uuidString, on: Date(), in: context).resolvedWork() == nil)
    }

    @Test("Launch repair relinks string-only check-ins and deletes true orphans only when told to")
    func repairRelinksAndDeletesOrphans() throws {
        let context = try makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes")
        CoreDataTestHelpers.save(context)
        let linked = seedStringOnlyCheckIn(workID: try #require(work.id?.uuidString), on: Date(), in: context)
        let orphan = seedStringOnlyCheckIn(workID: UUID().uuidString, on: Date(), in: context)
        CoreDataTestHelpers.save(context)

        let firstRun = DataCleanupService.repairWorkCheckInLinks(using: context, deleteOrphans: false)
        #expect(firstRun == .init(relinked: 1, orphansDeleted: 0, orphansKept: 1))
        #expect(linked.work === work)
        #expect(!orphan.isDeleted)

        let secondRun = DataCleanupService.repairWorkCheckInLinks(using: context, deleteOrphans: true)
        #expect(secondRun == .init(relinked: 0, orphansDeleted: 1, orphansKept: 0))
        CoreDataTestHelpers.save(context)
        #expect(checkIns(in: context).count == 1)
    }

    @Test("Deleting a work takes its check-ins with it, related or string-only")
    func deletingWorkCascadesToCheckIns() throws {
        let context = try makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Racks and tubes")
        let other = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame")
        CoreDataTestHelpers.save(context)
        CDWorkCheckIn.make(for: work, on: Date(), in: context)
        seedStringOnlyCheckIn(workID: try #require(work.id?.uuidString), on: Date(), in: context)
        let kept = seedStringOnlyCheckIn(workID: try #require(other.id?.uuidString), on: Date(), in: context)
        CoreDataTestHelpers.save(context)
        #expect(checkIns(in: context).count == 3)

        // The bare delete, not the service: the model itself must cascade.
        context.delete(work)
        CoreDataTestHelpers.save(context)

        let remaining = checkIns(in: context)
        #expect(remaining.count == 1)
        #expect(remaining.first === kept)
    }

    @Test("schedule_for_range names the work of a string-only check-in and flags a true orphan")
    func scheduleNamesWorkByString() async throws {
        let context = try makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Zahava", lastName: "Wechsler")
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Racks and tubes", studentID: try #require(student.id)
        )
        CoreDataTestHelpers.save(context)
        let day = try #require(MCPNotebookTools.isoDay.date(from: "2026-09-09"))
        seedStringOnlyCheckIn(workID: try #require(work.id?.uuidString), on: day, in: context)
        seedStringOnlyCheckIn(workID: UUID().uuidString, on: day, in: context)
        CoreDataTestHelpers.save(context)

        let tools = MCPNotebookTools.makeTools(context: { context })
        let schedule = try #require(tools.first { $0.name == "schedule_for_range" })
        let output = try await schedule.handler(["start_date": .string("2026-09-09")])

        #expect(output.contains("Racks and tubes — Zahava Wechsler"))
        #expect(output.contains("orphaned check-in"))
        #expect(!output.contains("unassigned"))
    }
}
