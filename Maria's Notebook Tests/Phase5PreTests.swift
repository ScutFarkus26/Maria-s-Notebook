import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@Suite("Phase 5 Pre-Tests: Sharing Prerequisites")
@MainActor
final class Phase5PreTests {

    // MARK: - Store Configuration

    @Test("CoreDataStack loads with both store configurations")
    func bothStoresLoad() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let stores = stack.container.persistentStoreCoordinator.persistentStores
        #expect(stores.count >= 2, "Expected at least 2 persistent stores (private + shared)")
    }

    // MARK: - ClassroomMembership CRUD

    @Test("CDClassroomMembership insert, save, and fetch")
    func classroomMembershipCreate() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        let membership = CoreDataTestHelpers.seedClassroomMembership(
            in: context,
            role: .leadGuide,
            zoneID: "zone-abc",
            ownerIdentity: "owner-123"
        )
        #expect(CoreDataTestHelpers.save(context))

        let request: NSFetchRequest<CDClassroomMembership> = NSFetchRequest(entityName: "ClassroomMembership")
        let results = context.safeFetch(request)
        #expect(results.count == 1)

        let fetched = results.first!
        #expect(fetched.classroomZoneID == "zone-abc")
        #expect(fetched.ownerIdentity == "owner-123")
        #expect(fetched.role == .leadGuide)
        #expect(fetched.id != nil)
        #expect(fetched.joinedAt != nil)

        _ = membership // suppress unused warning
    }

    @Test("CDClassroomMembership role update round-trip")
    func classroomMembershipRoleUpdate() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        let membership = CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        #expect(CoreDataTestHelpers.save(context))
        #expect(membership.role == .leadGuide)

        membership.role = .assistant
        #expect(CoreDataTestHelpers.save(context))

        let request: NSFetchRequest<CDClassroomMembership> = NSFetchRequest(entityName: "ClassroomMembership")
        let results = context.safeFetch(request)
        #expect(results.first?.role == .assistant)
        #expect(results.first?.roleRaw == "assistant")
    }

    @Test("CDClassroomMembership delete")
    func classroomMembershipDelete() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        let membership = CoreDataTestHelpers.seedClassroomMembership(in: context)
        #expect(CoreDataTestHelpers.save(context))

        context.delete(membership)
        #expect(CoreDataTestHelpers.save(context))

        let request: NSFetchRequest<CDClassroomMembership> = NSFetchRequest(entityName: "ClassroomMembership")
        let results = context.safeFetch(request)
        #expect(results.isEmpty)
    }

    // MARK: - Background Context

    @Test("Background context creation returns valid private-queue context")
    func backgroundContextCreation() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.newBackgroundContext()
        #expect(ctx.concurrencyType == .privateQueueConcurrencyType)
    }
}
