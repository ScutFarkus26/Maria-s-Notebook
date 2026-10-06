import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// Another running copy of the app is read, merged and announced, and each
/// store's history is purged only behind its own export (2026-10-05 hunt, #29,
/// #64). On-disk stores: in-memory ones keep no history.
@Suite("Persistent history: other processes and per-store purges")
@MainActor
struct PersistentHistoryProcessScopeTests {

    nonisolated private struct SuiteUnavailable: Error {}

    /// A defaults suite of the test's own, opened outside `#require` so it can
    /// be handed to the processor actor. The test reads the same suite through
    /// another instance (`suite`), as `Phase6PostTests` does.
    nonisolated private static func isolatedDefaults(_ suite: String = "history-scope-\(UUID().uuidString)") throws
        -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw SuiteUnavailable()
        }
        return defaults
    }

    // MARK: - Authors

    @Test("This process writes as itself; the old shared author still counts as its own")
    func authors() {
        let own = PersistentHistoryProcessor.transactionAuthor
        let legacy = PersistentHistoryProcessor.legacyTransactionAuthor
        let otherCopy = "\(legacy).99999.ABCDEF12"
        #expect(own != legacy)
        #expect(own.hasPrefix(legacy + "."))
        #expect(PersistentHistoryProcessor.isOwnAuthor(own))
        #expect(PersistentHistoryProcessor.isOwnAuthor(legacy))
        #expect(!PersistentHistoryProcessor.isOwnAuthor(otherCopy))
        #expect(PersistentHistoryProcessor.isFromAnotherProcess(author: otherCopy))
        #expect(!PersistentHistoryProcessor.isFromAnotherProcess(author: own))
        #expect(!PersistentHistoryProcessor.isFromAnotherProcess(author: legacy))
        #expect(!PersistentHistoryProcessor.isFromAnotherProcess(author: nil))
    }

    @Test("A CloudKit import isn't taken for another copy's save: this process's contexts merge it already")
    func importIsNotForeign() throws {
        let fixture = try TwoStoreHistoryFixture()
        defer { fixture.removeFiles() }
        try fixture.write(.privateStore, as: TwoStoreHistoryFixture.remoteAuthor)
        let transaction = try #require(try fixture.history(after: nil).last)
        // Every copy's process ID reads the same (the process's name), so it can't tell them apart.
        #expect(!PersistentHistoryProcessor.isFromAnotherProcess(author: transaction.author))
    }

    @Test("Another copy's save is read as remote and merged into this copy's view context")
    func anotherCopysSaveIsMerged() async throws {
        let fixture = try TwoStoreHistoryFixture()
        defer { fixture.removeFiles() }
        let viewContext = fixture.container.viewContext
        viewContext.transactionAuthor = PersistentHistoryProcessor.transactionAuthor
        let note = CoreDataTestHelpers.seedNote(in: viewContext, body: "Before")
        try viewContext.save()
        #expect(note.body == "Before")
        // What every copy wrote before: still this copy's own.
        try fixture.write(.privateStore, as: PersistentHistoryProcessor.legacyTransactionAuthor)

        // A second copy of the app on the same files edits the note.
        let otherCopy = try Self.container(on: fixture.directory)
        let otherContext = otherCopy.newBackgroundContext()
        otherContext.transactionAuthor = "\(PersistentHistoryProcessor.legacyTransactionAuthor).99999.ABCDEF12"
        let noteURI = note.objectID.uriRepresentation()
        try await otherContext.perform {
            let id = try #require(otherCopy.persistentStoreCoordinator.managedObjectID(forURIRepresentation: noteURI))
            let other = try #require(try otherContext.existingObject(with: id) as? CDNote)
            other.body = "After"
            try otherContext.save()
        }

        let processor = PersistentHistoryProcessor(container: fixture.container, defaults: try Self.isolatedDefaults())
        let foreign = await processor.processRemoteChanges()
        #expect(foreign.updated == [note.objectID])
        #expect(foreign.inserted.isEmpty)
        PersistentHistoryProcessor.merge(foreign, into: viewContext)
        #expect(note.body == "After")
    }

    /// Another container over the fixture's two store files, as a second copy
    /// of the app opens them.
    private static func container(on directory: URL) throws -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(
            name: CoreDataStack.modelName, managedObjectModel: try CoreDataStack.sharedModel()
        )
        container.persistentStoreDescriptions = [
            (CoreDataStack.privateConfiguration, "private.sqlite"),
            (CoreDataStack.sharedConfiguration, "shared.sqlite")
        ].map { configuration, file in
            let description = CoreDataStack.makeStoreDescription(
                url: directory.appendingPathComponent(file), configuration: configuration
            )
            CoreDataStack.enableHistoryTracking(description)
            return description
        }
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if let loadError { throw loadError }
        return container
    }

    // MARK: - Purging

    @Test("Each store's history is purged only behind that store's own last export")
    func purgeIsPerStore() async throws {
        let fixture = try TwoStoreHistoryFixture()
        defer { fixture.removeFiles() }
        try fixture.write(.privateStore)
        try fixture.write(.sharedStore)
        let suite = "history-scope-\(UUID().uuidString)"
        let defaults = try Self.isolatedDefaults(suite)
        let now = Date()
        // The classroom share exported after both writes; the notebook last did the day before.
        PersistentHistoryProcessor.recordExportStart(
            now.addingTimeInterval(-86_400), storeIdentifier: fixture.id(.privateStore), now: now, defaults: defaults
        )
        PersistentHistoryProcessor.recordExportStart(
            now, storeIdentifier: fixture.id(.sharedStore), now: now, defaults: defaults
        )

        let processor = PersistentHistoryProcessor(
            container: fixture.container, defaults: try Self.isolatedDefaults(suite)
        )
        // Seven months on: past the retention window, so only the exports gate it.
        await processor.purgeOldHistory(now: now.addingTimeInterval(210 * 86_400))

        #expect(try fixture.history(after: nil, scopedTo: [fixture.store(.privateStore)]).count == 1)
        #expect(try fixture.history(after: nil, scopedTo: [fixture.store(.sharedStore)]).isEmpty)
    }

    @Test("An export start dated in the future is never kept, and one left by a clock that ran ahead is replaced")
    func futureExportStartIgnored() throws {
        let defaults = try Self.isolatedDefaults()
        let now = Date()
        PersistentHistoryProcessor.recordExportStart(
            now.addingTimeInterval(3_600), storeIdentifier: "store", now: now, defaults: defaults
        )
        #expect(PersistentHistoryProcessor.exportStarts(in: defaults)["store"] == nil)

        let ahead = now.addingTimeInterval(30 * 86_400)
        defaults.set(
            ["store": ahead.timeIntervalSince1970], forKey: UserDefaultsKeys.cloudKitLastSuccessfulExportStartByStore
        )
        PersistentHistoryProcessor.recordExportStart(now, storeIdentifier: "store", now: now, defaults: defaults)
        let kept = try #require(PersistentHistoryProcessor.exportStarts(in: defaults)["store"])
        #expect(abs(kept.timeIntervalSince(now)) < 0.001)
    }

    @Test("A store whose only export start is in the future isn't purged")
    func futureStartDoesNotPurge() async throws {
        let fixture = try TwoStoreHistoryFixture()
        defer { fixture.removeFiles() }
        try fixture.write(.privateStore)
        let suite = "history-scope-\(UUID().uuidString)"
        let defaults = try Self.isolatedDefaults(suite)
        let ahead = Date().addingTimeInterval(400 * 86_400)
        defaults.set(
            [fixture.id(.privateStore): ahead.timeIntervalSince1970],
            forKey: UserDefaultsKeys.cloudKitLastSuccessfulExportStartByStore
        )
        let processor = PersistentHistoryProcessor(
            container: fixture.container, defaults: try Self.isolatedDefaults(suite)
        )
        await processor.purgeOldHistory()
        #expect(try fixture.history(after: nil, scopedTo: [fixture.store(.privateStore)]).count == 1)
        #expect(defaults.object(forKey: UserDefaultsKeys.persistentHistoryLastPurgeDate) == nil)
    }
}
