import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Bug hunt 2026-10-04, Phase 4, step 7: the Assistant never trimmed its
// persistent history (the notebook's processor is compiled out of it). The
// trim runs on two SQLite stores with history on, as on a phone, in a
// temporary folder: never the simulator's real store.
@Suite("Assistant history trim")
@MainActor
struct AssistantHistoryTrimTests {

    private let day: TimeInterval = 24 * 3600

    private struct Stores {
        let container: NSPersistentContainer
        let folder: URL
        let privateID: String
        let sharedID: String
    }

    private func makeStores() throws -> Stores {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryTrim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let container = NSPersistentContainer(name: "HistoryTrim", managedObjectModel: try CoreDataStack.sharedModel())
        container.persistentStoreDescriptions = [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration]
            .map { configuration in
                let url = folder.appendingPathComponent("\(configuration).sqlite")
                let description = NSPersistentStoreDescription(url: url)
                description.configuration = configuration
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                return description
            }
        var failures: [any Error] = []
        container.loadPersistentStores { _, error in
            if let error { failures.append(error) }
        }
        if let failure = failures.first { throw failure }
        let stores = container.persistentStoreCoordinator.persistentStores
        let privateStore = try #require(stores.first { $0.configurationName == CoreDataStack.privateConfiguration })
        let sharedStore = try #require(stores.first { $0.configurationName == CoreDataStack.sharedConfiguration })
        return Stores(
            container: container, folder: folder,
            privateID: try #require(privateStore.identifier), sharedID: try #require(sharedStore.identifier)
        )
    }

    /// One save into each store: a child in the class, a membership row in hers.
    private func saveIntoBoth(_ stores: Stores) throws {
        let context = stores.container.viewContext
        let all = stores.container.persistentStoreCoordinator.persistentStores
        let shared = try #require(all.first { $0.identifier == stores.sharedID })
        let privateStore = try #require(all.first { $0.identifier == stores.privateID })
        context.assign(AssistantTestSupport.student("Ari", "Cedar", in: context), to: shared)
        context.assign(CDClassroomMembership(context: context), to: privateStore)
        try context.save()
    }

    private func transactions(in storeID: String, _ stores: Stores) throws -> Int {
        let store = try #require(stores.container.persistentStoreCoordinator.persistentStores.first {
            $0.identifier == storeID
        })
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: .distantPast)
        request.resultType = .transactionsOnly
        request.affectedStores = [store]
        let result = try stores.container.viewContext.execute(request) as? NSPersistentHistoryResult
        let found = result?.result as? [NSPersistentHistoryTransaction] ?? []
        return found.filter { $0.storeID == storeID }.count
    }

    @Test("The cutoff is the earlier of the last export's start and 180 days ago")
    func cutoffRule() {
        let now = Date()
        let halfYearAgo = now.addingTimeInterval(-AssistantHistoryTrim.retention)
        #expect(AssistantHistoryTrim.cutoff(exportStart: now.addingTimeInterval(-3600), now: now) == halfYearAgo)
        let longAgo = now.addingTimeInterval(-200 * day)
        #expect(AssistantHistoryTrim.cutoff(exportStart: longAgo, now: now) == longAgo)
    }

    @Test("Only a store with a recorded export is trimmed, and only its own history")
    func trimsOnlyExportedStore() async throws {
        let stores = try makeStores()
        defer { try? FileManager.default.removeItem(at: stores.folder) }
        try saveIntoBoth(stores)
        let privateBefore = try transactions(in: stores.privateID, stores)
        #expect(privateBefore > 0)
        #expect(try transactions(in: stores.sharedID, stores) > 0)

        // The shared store exported after the saves; the private one never did.
        let defaults = AssistantTestSupport.makeDefaults()
        AssistantHistoryTrim.recordExport(storeIdentifier: stores.sharedID, startedAt: Date().addingTimeInterval(1),
                                          defaults: defaults)
        let yearOn = Date().addingTimeInterval(365 * day)
        let trimmed = await AssistantHistoryTrim.trim(stores.container, defaults: defaults, now: yearOn)

        #expect(trimmed == [stores.sharedID])
        #expect(try transactions(in: stores.sharedID, stores) == 0)
        #expect(try transactions(in: stores.privateID, stores) == privateBefore)
    }

    @Test("History newer than 180 days stays, even when exported")
    func keepsRecentHistory() async throws {
        let stores = try makeStores()
        defer { try? FileManager.default.removeItem(at: stores.folder) }
        try saveIntoBoth(stores)
        let before = try transactions(in: stores.sharedID, stores)
        let defaults = AssistantTestSupport.makeDefaults()
        AssistantHistoryTrim.recordExport(storeIdentifier: stores.sharedID, startedAt: Date().addingTimeInterval(1),
                                          defaults: defaults)
        await AssistantHistoryTrim.trim(stores.container, defaults: defaults, now: Date())
        #expect(try transactions(in: stores.sharedID, stores) == before)
    }

    @Test("A store is trimmed at most every 60 days, and its export start only moves forward")
    func intervalAndForwardOnly() async throws {
        let stores = try makeStores()
        defer { try? FileManager.default.removeItem(at: stores.folder) }
        let defaults = AssistantTestSupport.makeDefaults()
        let start = Date().addingTimeInterval(1)
        AssistantHistoryTrim.recordExport(storeIdentifier: stores.sharedID, startedAt: start, defaults: defaults)
        AssistantHistoryTrim.recordExport(storeIdentifier: stores.sharedID, startedAt: start.addingTimeInterval(-60),
                                          defaults: defaults)
        #expect(AssistantHistoryTrim.exportStarts(defaults)[stores.sharedID] == start)

        let yearOn = Date().addingTimeInterval(365 * day)
        #expect(await AssistantHistoryTrim.trim(stores.container, defaults: defaults, now: yearOn) == [stores.sharedID])
        #expect(await AssistantHistoryTrim.trim(stores.container, defaults: defaults, now: yearOn + 59 * day).isEmpty)
        #expect(await AssistantHistoryTrim.trim(stores.container, defaults: defaults, now: yearOn + 61 * day)
            == [stores.sharedID])
    }
}
