import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// When each store last finished a CloudKit import, for the repairs that wait
/// out a download (2026-10-05 hunt, #22).
@Suite("Import watermark")
@MainActor
struct ImportWatermarkTests {

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "import-watermark-\(UUID().uuidString)"))
    }

    @Test("Each store keeps the start of its own last finished import, and it only moves forward")
    func perStoreForwardOnly() throws {
        let defaults = try makeDefaults()
        let now = Date()
        let earlier = now.addingTimeInterval(-3_600)
        ImportWatermark.record(importStartedAt: earlier, storeIdentifier: "private", now: now, defaults: defaults)
        ImportWatermark.record(importStartedAt: now, storeIdentifier: "shared", now: now, defaults: defaults)
        // A late event for an older import doesn't move it back.
        ImportWatermark.record(
            importStartedAt: earlier.addingTimeInterval(-60), storeIdentifier: "private", now: now, defaults: defaults
        )
        #expect(ImportWatermark.lastImport(intoStoreWithIdentifier: "private", now: now, defaults: defaults) == earlier)
        #expect(ImportWatermark.lastImport(intoStoreWithIdentifier: "shared", now: now, defaults: defaults) == now)
        #expect(ImportWatermark.lastImport(intoStoreWithIdentifier: "other", now: now, defaults: defaults) == nil)
    }

    @Test("A start dated in the future is never taken, so it can't read as an import after anything")
    func futureStartsIgnored() throws {
        let defaults = try makeDefaults()
        let now = Date()
        ImportWatermark.record(
            importStartedAt: now.addingTimeInterval(600), storeIdentifier: "private", now: now, defaults: defaults
        )
        #expect(ImportWatermark.lastImport(intoStoreWithIdentifier: "private", now: now, defaults: defaults) == nil)

        // Recorded while the clock ran a day ahead, then the clock came back.
        let ahead = now.addingTimeInterval(86_400)
        ImportWatermark.record(importStartedAt: ahead, storeIdentifier: "private", now: ahead, defaults: defaults)
        #expect(ImportWatermark.lastImport(intoStoreWithIdentifier: "private", now: now, defaults: defaults) == nil)
        ImportWatermark.record(importStartedAt: now, storeIdentifier: "private", now: now, defaults: defaults)
        #expect(ImportWatermark.lastImport(intoStoreWithIdentifier: "private", now: now, defaults: defaults) == now)
    }

    @Test("A store replaced by a reset has no import until its own first one")
    func replacedStoreForgotten() throws {
        let defaults = try makeDefaults()
        let now = Date()
        ImportWatermark.record(importStartedAt: now, storeIdentifier: "old-private", now: now, defaults: defaults)
        ImportWatermark.record(
            importStartedAt: now, storeIdentifier: "new-shared", liveStoreIdentifiers: ["new-private", "new-shared"],
            now: now, defaults: defaults
        )
        #expect(ImportWatermark.lastImport(intoStoreWithIdentifier: "old-private", now: now, defaults: defaults) == nil)
        #expect(ImportWatermark.lastImport(intoStoreWithIdentifier: "new-private", now: now, defaults: defaults) == nil)
    }

    @Test("Read by store kind from a stack: the notebook is the private store")
    func readByKind() throws {
        let defaults = try makeDefaults()
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let privateStore = try stack.container.persistentStoreCoordinator.addPersistentStore(
            type: .inMemory,
            configuration: CoreDataStack.privateConfiguration,
            at: URL(fileURLWithPath: "/dev/null/private-\(UUID().uuidString)")
        )
        let now = Date()
        ImportWatermark.record(
            importStartedAt: now, storeIdentifier: privateStore.identifier, now: now, defaults: defaults
        )
        #expect(ImportWatermark.lastImport(into: .notebook, of: stack, now: now, defaults: defaults) == now)
        #expect(ImportWatermark.lastImport(into: .classroomShare, of: stack, now: now, defaults: defaults) == nil)
    }
}
