import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

@Suite("Phase 6 Post-Tests: Conflict Resolution & Offline")
@MainActor
final class Phase6PostTests {

    // Every processor here reads on-disk stores and keeps its cursor in a
    // defaults suite of its own. An in-memory store rejects every history
    // fetch (NSCocoaErrorDomain 134091), and so do these stores when given
    // the test host's cursor from `.standard`, a token from another store
    // (134501). A pass whose fetch throws fails open: it posts the
    // school-day and presentation notifications process-wide and asks the
    // shared dedup coordinator for a full sweep.

    nonisolated private struct SuiteUnavailable: Error {}

    /// The processor's handle on a test's defaults suite. Opened here rather
    /// than with `#require`, whose result belongs to the main actor and so
    /// could not be handed to the processor actor.
    nonisolated private static func processorDefaults(suite: String) throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suite) else { throw SuiteUnavailable() }
        return defaults
    }

    private func makeProcessor(
        over stores: OnDiskHistoryStores,
        keepingIn defaults: IsolatedDefaults
    ) throws -> PersistentHistoryProcessor {
        PersistentHistoryProcessor(
            container: stores.container,
            defaults: try Self.processorDefaults(suite: defaults.suiteName)
        )
    }

    // MARK: - Token Tracking

    @Test("PersistentHistoryProcessor init loads without crash")
    func processorInit() async throws {
        let stores = try OnDiskHistoryStores()
        defer { stores.cleanUp() }
        let defaults = try IsolatedDefaults()
        defer { defaults.cleanUp() }

        // A previous launch read the app's own write, which the processor
        // skips but moves its cursor past, and saved where it got to.
        try stores.saveOwnWrite()
        let previousLaunch = try makeProcessor(over: stores, keepingIn: defaults)
        await previousLaunch.processRemoteChanges()
        let saved = defaults.contents
        try #require(saved.count > 0, "the first pass saved no cursor")

        // Construction loads that cursor, and a pass with nothing after it
        // keeps it. A pass that could not read would drop it as stale.
        let processor = try makeProcessor(over: stores, keepingIn: defaults)
        await processor.processRemoteChanges()
        #expect(defaults.contents == saved)
    }

    @Test("processRemoteChanges completes without crash on empty history")
    func processRemoteChangesEmpty() async throws {
        let stores = try OnDiskHistoryStores()
        defer { stores.cleanUp() }
        let defaults = try IsolatedDefaults()
        defer { defaults.cleanUp() }
        // Empty history reads back as no transactions, not as an error.
        #expect(try stores.transactions().isEmpty)

        let processor = try makeProcessor(over: stores, keepingIn: defaults)
        await processor.processRemoteChanges()
        // With no transaction to move past, the pass saves no cursor.
        #expect(defaults.contents.count == 0)
    }

    // MARK: - Author Filtering

    @Test("Transaction author constant is set correctly")
    func transactionAuthorConstant() {
        #expect(PersistentHistoryProcessor.transactionAuthor == "CosmicDaybook")
    }

    @Test("View context has transactionAuthor set")
    func viewContextAuthor() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        #expect(stack.viewContext.transactionAuthor == PersistentHistoryProcessor.transactionAuthor)
    }

    @Test("Background context has transactionAuthor set")
    func backgroundContextAuthor() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let bgCtx = stack.newBackgroundContext()
        #expect(bgCtx.transactionAuthor == PersistentHistoryProcessor.transactionAuthor)
    }

    // MARK: - History Cleanup

    @Test("purgeOldHistory completes without crash on empty history")
    func purgeOldHistory() async throws {
        let stores = try OnDiskHistoryStores()
        defer { stores.cleanUp() }
        let defaults = try IsolatedDefaults()
        defer { defaults.cleanUp() }
        // An export on record, so the purge goes as far as the history.
        let exported = Date().timeIntervalSince1970
        defaults.store.set(exported, forKey: UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate)
        let processor = try makeProcessor(over: stores, keepingIn: defaults)

        await processor.purgeOldHistory()

        // Only a delete that succeeded records its date.
        let purged = defaults.store.object(forKey: UserDefaultsKeys.persistentHistoryLastPurgeDate) as? TimeInterval
        let purgedAt = try #require(purged)
        #expect(purgedAt >= exported)
    }

    @Test("purgeOldHistory is a no-op until CloudKit has successfully exported")
    func purgeSkipsWithoutExportDate() async throws {
        let stores = try OnDiskHistoryStores()
        defer { stores.cleanUp() }
        let defaults = try IsolatedDefaults()
        defer { defaults.cleanUp() }
        let processor = try makeProcessor(over: stores, keepingIn: defaults)

        await processor.purgeOldHistory()

        // Without a recorded export the purge must not run, and must not
        // record a purge date — the mirroring delegate's history cursor
        // could still point anywhere in the un-exported history.
        #expect(defaults.store.object(forKey: UserDefaultsKeys.persistentHistoryLastPurgeDate) == nil)
    }

    // MARK: - End-to-End Merge

    @Test("Insert on background context merges to viewContext")
    func endToEndMerge() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let bgCtx = stack.newBackgroundContext()

        await bgCtx.perform {
            let student = CDStudent(context: bgCtx)
            student.firstName = "Phase6"
            student.lastName = "MergeTest"
            try? bgCtx.save()
        }

        // Allow merge to propagate (automaticallyMergesChangesFromParent)
        try await Task.sleep(for: .milliseconds(200))

        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "firstName == %@", "Phase6")
        let results = stack.viewContext.safeFetch(request)
        #expect(results.count == 1)
        #expect(results.first?.lastName == "MergeTest")
    }

    // MARK: - CoreDataStack Integration

    @Test("Secondary stacks (in-memory, Sample Class) do not create a history processor")
    func secondaryStackHasNoProcessor() throws {
        // History tokens are per-store and every processor persists its token
        // under the same UserDefaults key, so only the primary on-disk stack
        // may own a processor — a secondary stack's saves would clobber the
        // primary cursor with one referencing a different store file.
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        #expect(stack.historyProcessor == nil)
    }
}

/// A throwaway defaults suite, so no test reads or moves the cursor the test
/// host's own processor keeps in `.standard`.
private struct IsolatedDefaults {
    let suiteName: String
    let store: UserDefaults

    init() throws {
        let name = "phase6-history-\(UUID().uuidString)"
        suiteName = name
        store = try #require(UserDefaults(suiteName: name))
    }

    /// Everything written to the suite, whatever keys the processor uses.
    var contents: NSDictionary {
        (store.persistentDomain(forName: suiteName) ?? [:]) as NSDictionary
    }

    func cleanUp() {
        store.removePersistentDomain(forName: suiteName)
    }
}

/// The primary stack's two stores as the history processor reads them: two
/// on-disk SQLite stores with the production Private and Shared
/// configurations and history tracking on both, private first as in
/// production. Freshly loaded, they have no history at all.
@MainActor
private struct OnDiskHistoryStores {
    let directory: URL
    let container: NSPersistentCloudKitContainer

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase6-history-\(UUID().uuidString)", isDirectory: true)
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
        self.directory = directory
        self.container = container
    }

    /// Both stores' whole history, read as a plain fetch.
    func transactions() throws -> [NSPersistentHistoryTransaction] {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
        let result = try container.viewContext.execute(request) as? NSPersistentHistoryResult
        return try #require(result?.result as? [NSPersistentHistoryTransaction])
    }

    /// Saves one note as the app itself: history the processor's remote
    /// filter skips, so a pass over it only moves the cursor — no
    /// notification, no dedup request.
    func saveOwnWrite() throws {
        let context = container.viewContext
        context.transactionAuthor = PersistentHistoryProcessor.transactionAuthor
        CoreDataTestHelpers.seedNote(in: context, body: "own write")
        try context.save()
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
