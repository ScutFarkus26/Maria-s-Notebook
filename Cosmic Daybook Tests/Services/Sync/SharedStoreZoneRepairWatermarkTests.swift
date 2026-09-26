import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// Pins where the zone-repair gate's clean watermark moves and which history
/// a pass reads. A pass whose read finds no shared insert moves the watermark
/// up to the token it took before reading, so the next pass reads only what
/// landed since; an insert that lands at any point after that token still
/// opens the gate; and only the private store's history — where every orphan
/// lives — is read. On-disk SQLite, because in-memory stores keep no history.
@Suite("Shared-store zone repair: clean watermark")
@MainActor
struct SharedStoreZoneRepairWatermarkTests {

    private let sharedNames: Set<String> = ["Student"]

    /// One automatic pass's gate step in production order (`scanScope`,
    /// `refreshCountsIfNeeded`): take the store's token, read history since
    /// the watermark, move the watermark on a clean verdict.
    private func gatePass(
        _ fixture: HistoryFixture,
        defaults: UserDefaults
    ) async throws -> SharedStoreZoneRepair.GateDecision {
        let tokenBefore = try fixture.token()
        let decision = await SharedStoreZoneRepair.gateDecision(
            since: SharedStoreZoneRepair.loadCleanToken(defaults: defaults),
            store: fixture.store, container: fixture.container, sharedEntityNames: sharedNames
        )
        SharedStoreZoneRepair.advanceCleanToken(after: decision, to: tokenBefore, defaults: defaults)
        return decision
    }

    private func decision(
        since token: NSPersistentHistoryToken?,
        in fixture: HistoryFixture
    ) async -> SharedStoreZoneRepair.GateDecision {
        await SharedStoreZoneRepair.gateDecision(
            since: token, store: fixture.store, container: fixture.container, sharedEntityNames: sharedNames
        )
    }

    @Test("A clean pass moves the watermark up to the token taken before its read")
    func cleanPassAdvancesWatermark() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.cleanUp() }
        let defaults = try IsolatedDefaults()
        defer { defaults.cleanUp() }
        let lastScan = try fixture.token()
        SharedStoreZoneRepair.saveCleanToken(lastScan, defaults: defaults.store)

        CoreDataTestHelpers.seedNote(in: fixture.context, body: "remote batch")
        #expect(CoreDataTestHelpers.save(fixture.context))
        let tokenBefore = try fixture.token()

        let decision = try await gatePass(fixture, defaults: defaults.store)
        #expect(decision == .clean)
        let watermark = SharedStoreZoneRepair.loadCleanToken(defaults: defaults.store)
        #expect(watermark == tokenBefore)
        #expect(watermark != lastScan)
    }

    @Test("Each clean pass reads only what landed since the pass before it")
    func passesReadOnlySinceThePreviousPass() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.cleanUp() }
        let defaults = try IsolatedDefaults()
        defer { defaults.cleanUp() }
        let lastScan = try fixture.token()
        SharedStoreZoneRepair.saveCleanToken(lastScan, defaults: defaults.store)

        var readPerPass: [Int] = []
        for batch in 1...5 {
            CoreDataTestHelpers.seedNote(in: fixture.context, body: "remote batch \(batch)")
            #expect(CoreDataTestHelpers.save(fixture.context))
            let watermark = try #require(SharedStoreZoneRepair.loadCleanToken(defaults: defaults.store))
            readPerPass.append(try fixture.transactionsRead(after: watermark))
            let decision = try await gatePass(fixture, defaults: defaults.store)
            #expect(decision == .clean)
        }
        // With the watermark parked at the last scan, pass k re-read all k
        // batches since it (1, 2, 3, 4, 5 — 15 transactions for five passes).
        #expect(readPerPass == [1, 1, 1, 1, 1])
        #expect(try fixture.transactionsRead(after: lastScan) == 5)
    }

    @Test("A shared insert after a clean pass still opens the gate")
    func sharedInsertAfterCleanPassScans() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.cleanUp() }
        let defaults = try IsolatedDefaults()
        defer { defaults.cleanUp() }
        SharedStoreZoneRepair.saveCleanToken(try fixture.token(), defaults: defaults.store)
        CoreDataTestHelpers.seedNote(in: fixture.context, body: "remote batch")
        #expect(CoreDataTestHelpers.save(fixture.context))
        let cleanPass = try await gatePass(fixture, defaults: defaults.store)
        #expect(cleanPass == .clean)
        let advanced = SharedStoreZoneRepair.loadCleanToken(defaults: defaults.store)

        let student = CoreDataTestHelpers.seedStudent(in: fixture.context, firstName: "Maya", lastName: "S")
        #expect(CoreDataTestHelpers.save(fixture.context))

        let next = try await gatePass(fixture, defaults: defaults.store)
        #expect(next == .scan(entityNames: ["Student"], objectIDs: [student.objectID]))
        // A scan verdict leaves the watermark for the scan itself to move.
        #expect(SharedStoreZoneRepair.loadCleanToken(defaults: defaults.store) == advanced)
    }

    @Test("An insert between the history read and the watermark write still opens the gate")
    func insertAfterTheReadStillScans() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.cleanUp() }
        let defaults = try IsolatedDefaults()
        defer { defaults.cleanUp() }
        SharedStoreZoneRepair.saveCleanToken(try fixture.token(), defaults: defaults.store)
        CoreDataTestHelpers.seedNote(in: fixture.context, body: "remote batch")
        #expect(CoreDataTestHelpers.save(fixture.context))

        let tokenBefore = try fixture.token()
        let verdict = await decision(since: SharedStoreZoneRepair.loadCleanToken(defaults: defaults.store), in: fixture)
        #expect(verdict == .clean)
        let late = CoreDataTestHelpers.seedStudent(in: fixture.context, firstName: "Late", lastName: "L")
        #expect(CoreDataTestHelpers.save(fixture.context))
        SharedStoreZoneRepair.advanceCleanToken(after: verdict, to: tokenBefore, defaults: defaults.store)

        let next = try await gatePass(fixture, defaults: defaults.store)
        #expect(next == .scan(entityNames: ["Student"], objectIDs: [late.objectID]))
    }

    @Test("An insert between the token and the history read keeps the watermark in place")
    func insertBeforeTheReadKeepsWatermark() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.cleanUp() }
        let defaults = try IsolatedDefaults()
        defer { defaults.cleanUp() }
        let lastScan = try fixture.token()
        SharedStoreZoneRepair.saveCleanToken(lastScan, defaults: defaults.store)
        CoreDataTestHelpers.seedNote(in: fixture.context, body: "remote batch")
        #expect(CoreDataTestHelpers.save(fixture.context))

        let tokenBefore = try fixture.token()
        #expect(tokenBefore != lastScan)
        let early = CoreDataTestHelpers.seedStudent(in: fixture.context, firstName: "Early", lastName: "E")
        #expect(CoreDataTestHelpers.save(fixture.context))
        let verdict = await decision(since: lastScan, in: fixture)
        #expect(verdict == .scan(entityNames: ["Student"], objectIDs: [early.objectID]))
        SharedStoreZoneRepair.advanceCleanToken(after: verdict, to: tokenBefore, defaults: defaults.store)

        #expect(SharedStoreZoneRepair.loadCleanToken(defaults: defaults.store) == lastScan)
        let next = try await gatePass(fixture, defaults: defaults.store)
        #expect(next == verdict)
    }

    @Test("Only a clean verdict with a token moves the watermark")
    func onlyCleanVerdictsMoveTheWatermark() throws {
        let fixture = try HistoryFixture()
        defer { fixture.cleanUp() }
        let defaults = try IsolatedDefaults()
        defer { defaults.cleanUp() }
        let original = try fixture.token()
        SharedStoreZoneRepair.saveCleanToken(original, defaults: defaults.store)
        CoreDataTestHelpers.seedNote(in: fixture.context, body: "remote batch")
        #expect(CoreDataTestHelpers.save(fixture.context))
        let later = try fixture.token()

        let scans: [SharedStoreZoneRepair.GateDecision] = [
            .scan(entityNames: ["Student"], objectIDs: []), .scanEverything(reason: "test")
        ]
        for verdict in scans {
            SharedStoreZoneRepair.advanceCleanToken(after: verdict, to: later, defaults: defaults.store)
        }
        SharedStoreZoneRepair.advanceCleanToken(after: .clean, to: nil, defaults: defaults.store)
        #expect(SharedStoreZoneRepair.loadCleanToken(defaults: defaults.store) == original)

        SharedStoreZoneRepair.advanceCleanToken(after: .clean, to: later, defaults: defaults.store)
        #expect(SharedStoreZoneRepair.loadCleanToken(defaults: defaults.store) == later)
    }

    @Test("The gate reads only the private store's history")
    func gateReadsOnlyThePrivateStore() async throws {
        let fixture = try SplitHistoryFixture()
        defer { fixture.cleanUp() }
        let context = fixture.container.viewContext
        let watermark = try #require(
            SharedStoreZoneRepair.currentHistoryToken(for: fixture.privateStore, in: fixture.container)
        )
        let request = SharedStoreZoneRepair.gateHistoryRequest(after: watermark, in: fixture.privateStore)
        #expect(request.affectedStores == [fixture.privateStore])

        // A classroom row in the shared store (an accepted share) is never a
        // private-store orphan — detection reads only the private store — so
        // it must not open the gate.
        let accepted = CoreDataTestHelpers.seedStudent(in: context, firstName: "Accepted", lastName: "A")
        context.assign(accepted, to: fixture.sharedStore)
        #expect(CoreDataTestHelpers.save(context))
        let afterShared = await SharedStoreZoneRepair.gateDecision(
            since: watermark, store: fixture.privateStore, container: fixture.container, sharedEntityNames: sharedNames
        )
        #expect(afterShared == .clean)

        // The same entity inserted into the private store still opens it,
        // scoped to exactly that row.
        let own = CoreDataTestHelpers.seedStudent(in: context, firstName: "Own", lastName: "O")
        #expect(CoreDataTestHelpers.save(context))
        #expect(own.objectID.persistentStore == fixture.privateStore)
        let afterPrivate = await SharedStoreZoneRepair.gateDecision(
            since: watermark, store: fixture.privateStore, container: fixture.container, sharedEntityNames: sharedNames
        )
        #expect(afterPrivate == .scan(entityNames: ["Student"], objectIDs: [own.objectID]))
    }
}

/// A throwaway defaults suite, so no test reads or moves the app's own watermark.
private struct IsolatedDefaults {
    let suiteName: String
    let store: UserDefaults

    init() throws {
        let name = "zone-watermark-\(UUID().uuidString)"
        suiteName = name
        store = try #require(UserDefaults(suiteName: name))
    }

    func cleanUp() {
        store.removePersistentDomain(forName: suiteName)
    }
}

/// A single on-disk store with persistent history, the layout the gate reads
/// in production reduced to its private store.
@MainActor
private struct HistoryFixture {
    let directory: URL
    let stack: CoreDataStack
    let store: NSPersistentStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zone-watermark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stack = try CoreDataStack(enableCloudKit: false, localStoreURL: directory.appendingPathComponent("gate.sqlite"))
        store = try #require(stack.container.persistentStoreCoordinator.persistentStores.first)
    }

    var container: NSPersistentCloudKitContainer { stack.container }
    var context: NSManagedObjectContext { stack.viewContext }

    func token() throws -> NSPersistentHistoryToken {
        try #require(SharedStoreZoneRepair.currentHistoryToken(for: store, in: container))
    }

    /// How many transactions the gate's own request returns after `token` —
    /// what a pass starting from that watermark reads.
    func transactionsRead(after token: NSPersistentHistoryToken) throws -> Int {
        let request = SharedStoreZoneRepair.gateHistoryRequest(after: token, in: store)
        let result = try context.execute(request) as? NSPersistentHistoryResult
        let transactions = try #require(result?.result as? [NSPersistentHistoryTransaction])
        return transactions.count
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Two on-disk stores with the production Private and Shared configurations
/// and history tracking on both, private first as in production, so an
/// unassigned insert lands in the private store.
@MainActor
private struct SplitHistoryFixture {
    let directory: URL
    let container: NSPersistentCloudKitContainer
    let privateStore: NSPersistentStore
    let sharedStore: NSPersistentStore

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zone-split-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = NSPersistentCloudKitContainer(
            name: CoreDataStack.modelName, managedObjectModel: try CoreDataStack.sharedModel()
        )
        let configurations = [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration]
        container.persistentStoreDescriptions = configurations.map { configuration in
            let description = CoreDataStack.makeStoreDescription(
                url: directory.appendingPathComponent("\(configuration).sqlite"), configuration: configuration
            )
            CoreDataStack.enableHistoryTracking(description)
            return description
        }
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if let loadError { throw loadError }
        let stores = container.persistentStoreCoordinator.persistentStores
        self.directory = directory
        self.container = container
        privateStore = try #require(stores.first { $0.configurationName == CoreDataStack.privateConfiguration })
        sharedStore = try #require(stores.first { $0.configurationName == CoreDataStack.sharedConfiguration })
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
