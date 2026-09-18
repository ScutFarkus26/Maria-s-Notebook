import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the persistent-history gate in front of the shared-store zone repair:
/// the pass must skip when nothing shared was inserted, scope itself to the
/// entities that were, and fall open to a full scan whenever history cannot
/// answer. Uses an on-disk SQLite stack because in-memory stores keep no
/// persistent history.
@Suite("Shared-store zone repair: history gate")
@MainActor
struct SharedStoreZoneRepairGateTests {

    private struct Fixture {
        let stack: CoreDataStack
        let store: NSPersistentStore
        let directory: URL

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zone-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stack = try CoreDataStack(
            enableCloudKit: false,
            localStoreURL: directory.appendingPathComponent("gate.sqlite")
        )
        let store = try #require(stack.container.persistentStoreCoordinator.persistentStores.first)
        return Fixture(stack: stack, store: store, directory: directory)
    }

    private func token(_ fixture: Fixture) throws -> NSPersistentHistoryToken {
        try #require(SharedStoreZoneRepair.currentHistoryToken(for: fixture.store, in: fixture.stack.container))
    }

    private let sharedNames: Set<String> = ["Student"]

    @Test("Without a clean watermark the pass scans everything")
    func noWatermarkScansEverything() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let decision = await SharedStoreZoneRepair.gateDecision(
            since: nil, container: fixture.stack.container, sharedEntityNames: sharedNames
        )
        guard case .scanEverything = decision else {
            Issue.record("expected scanEverything, got \(decision)")
            return
        }
    }

    @Test("Inserting a non-shared entity leaves the gate clean")
    func nonSharedInsertIsClean() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let watermark = try token(fixture)

        CoreDataTestHelpers.seedNote(in: fixture.stack.viewContext, body: "not classroom data")
        #expect(CoreDataTestHelpers.save(fixture.stack.viewContext))

        let decision = await SharedStoreZoneRepair.gateDecision(
            since: watermark, container: fixture.stack.container, sharedEntityNames: sharedNames
        )
        #expect(decision == .clean)
    }

    @Test("Inserting a shared entity scopes the scan to that entity")
    func sharedInsertScopesToThatEntity() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let watermark = try token(fixture)

        CoreDataTestHelpers.seedStudent(in: fixture.stack.viewContext, firstName: "Maya", lastName: "S")
        CoreDataTestHelpers.seedNote(in: fixture.stack.viewContext)
        #expect(CoreDataTestHelpers.save(fixture.stack.viewContext))

        let decision = await SharedStoreZoneRepair.gateDecision(
            since: watermark, container: fixture.stack.container, sharedEntityNames: sharedNames
        )
        #expect(decision == .scan(entityNames: ["Student"]))
    }

    @Test("Updating an existing shared record does not reopen the gate")
    func updatesDoNotReopenTheGate() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let context = fixture.stack.viewContext

        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        #expect(CoreDataTestHelpers.save(context))
        let watermark = try token(fixture)

        student.firstName = "Mira"
        #expect(CoreDataTestHelpers.save(context))

        let decision = await SharedStoreZoneRepair.gateDecision(
            since: watermark, container: fixture.stack.container, sharedEntityNames: sharedNames
        )
        #expect(decision == .clean)
    }

    @Test("The clean watermark survives a round trip through UserDefaults")
    func cleanTokenRoundTrips() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let suiteName = "zone-gate-defaults-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CoreDataTestHelpers.seedStudent(in: fixture.stack.viewContext)
        #expect(CoreDataTestHelpers.save(fixture.stack.viewContext))
        let watermark = try token(fixture)

        #expect(SharedStoreZoneRepair.loadCleanToken(defaults: defaults) == nil)
        SharedStoreZoneRepair.saveCleanToken(watermark, defaults: defaults)
        #expect(SharedStoreZoneRepair.loadCleanToken(defaults: defaults) == watermark)
        SharedStoreZoneRepair.clearCleanToken(defaults: defaults)
        #expect(SharedStoreZoneRepair.loadCleanToken(defaults: defaults) == nil)
    }

    @Test("Candidate IDs cover only the scoped entities and fetch no objects")
    func candidateIDsAreScopedToEntity() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let context = fixture.stack.viewContext

        for name in ["Ada", "Ben", "Cy"] {
            CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "T")
        }
        CoreDataTestHelpers.seedNote(in: context)
        #expect(CoreDataTestHelpers.save(context))

        let scope = SharedStoreZoneRepair.RepairScope(
            entityNames: ["Student"], store: fixture.store, container: fixture.stack.container
        )
        let candidates = await SharedStoreZoneRepair.candidateIDs(in: scope)
        #expect(candidates.count == 3)
        #expect(Set(candidates.map(\.entityName)) == ["Student"])
    }
}
