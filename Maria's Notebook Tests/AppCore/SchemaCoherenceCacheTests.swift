import CoreData
import Foundation
import SQLite3
import Testing
@testable import Maria_s_Notebook

// MARK: - Physical Schema Coherence Cache
//
// `prepareStoresForLoad` walks PRAGMA table_info for every table on every
// launch to catch stores whose metadata lies about their columns. The cache
// lets a launch skip that walk when the same compiled model was already
// verified against the same on-disk DDL, keyed on a digest of
// `sqlite_master`. These tests pin the two properties that make the skip
// safe: the key is stable while nothing changes the tables and indexes
// (including across a Core Data reopen, which runs transient DDL), and any
// real DDL — even from a foreign connection — produces a different key.

@Suite("Physical schema coherence cache")
@MainActor
struct SchemaCoherenceCacheTests {

    // MARK: - Fixtures

    /// A freshly built on-disk unified store, closed so the file is quiescent.
    private func makeClosedStore() throws -> (url: URL, model: NSManagedObjectModel) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("unified.sqlite")

        let stack = try CoreDataStack(enableCloudKit: false, localStoreURL: url)
        let coordinator = stack.container.persistentStoreCoordinator
        let model = coordinator.managedObjectModel
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
        return (url, model)
    }

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "SchemaCoherenceCacheTests.\(UUID().uuidString)"))
    }

    /// Runs one DDL statement through a plain SQLite connection, standing in
    /// for another build migrating the file behind this one's back.
    private func runDDL(_ sql: String, at url: URL) throws {
        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        try #require(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
    }

    // MARK: - Tests

    @Test("a store that exists has a key, and the key is stable")
    func keyIsStableForUnchangedStore() throws {
        let (url, model) = try makeClosedStore()
        let first = try #require(CoreDataStack.schemaCoherenceKey(storeURL: url, model: model))
        let second = try #require(CoreDataStack.schemaCoherenceKey(storeURL: url, model: model))
        #expect(first == second)
        #expect(first.hasPrefix(CoreDataStack.modelSchemaDigest(model)))
    }

    @Test("a missing file has no key, so nothing is cached for it")
    func missingFileHasNoKey() throws {
        let (url, model) = try makeClosedStore()
        let missing = url.deletingLastPathComponent().appendingPathComponent("absent.sqlite")
        #expect(CoreDataStack.schemaCoherenceKey(storeURL: missing, model: model) == nil)
        #expect(CoreDataStack.sqliteSchemaDigest(storeURL: missing) == nil)
    }

    @Test("an unverified store is not skipped; a recorded one is")
    func recordThenVerify() throws {
        let (url, model) = try makeClosedStore()
        let defaults = try makeDefaults()
        let key = try #require(CoreDataStack.schemaCoherenceKey(storeURL: url, model: model))

        #expect(!CoreDataStack.isSchemaCoherenceVerified(storeURL: url, key: key, defaults: defaults))
        CoreDataStack.recordSchemaCoherenceVerified(storeURL: url, key: key, defaults: defaults)
        #expect(CoreDataStack.isSchemaCoherenceVerified(storeURL: url, key: key, defaults: defaults))
    }

    @Test("DDL from another connection invalidates the recorded key")
    func foreignDDLInvalidates() throws {
        let (url, model) = try makeClosedStore()
        let defaults = try makeDefaults()
        let before = try #require(CoreDataStack.schemaCoherenceKey(storeURL: url, model: model))
        CoreDataStack.recordSchemaCoherenceVerified(storeURL: url, key: before, defaults: defaults)

        try runDDL("CREATE TABLE ZSCAR (Z_PK INTEGER PRIMARY KEY)", at: url)

        let after = try #require(CoreDataStack.schemaCoherenceKey(storeURL: url, model: model))
        #expect(after != before)
        #expect(!CoreDataStack.isSchemaCoherenceVerified(storeURL: url, key: after, defaults: defaults))
    }

    @Test("reopening through Core Data and writing rows does not change the key")
    func rowWritesKeepKey() throws {
        let (url, model) = try makeClosedStore()
        let before = try #require(CoreDataStack.schemaCoherenceKey(storeURL: url, model: model))

        // Reopen through Core Data, insert a row, save, close.
        let stack = try CoreDataStack(enableCloudKit: false, localStoreURL: url)
        CoreDataTestHelpers.seedStudent(in: stack.viewContext, firstName: "Key", lastName: "Stable")
        #expect(CoreDataTestHelpers.save(stack.viewContext))
        let coordinator = stack.container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }

        let after = try #require(CoreDataStack.schemaCoherenceKey(storeURL: url, model: model))
        #expect(after == before)
    }

    @Test("dropping an index changes the key")
    func indexDropInvalidates() throws {
        let (url, model) = try makeClosedStore()
        let before = try #require(CoreDataStack.schemaCoherenceKey(storeURL: url, model: model))

        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }

        // Read the name in its own scope so the SELECT is finalized before the
        // DROP runs; an open statement on the same connection makes DDL return
        // SQLITE_LOCKED.
        let index: String = try {
            var statement: OpaquePointer?
            try #require(sqlite3_prepare_v2(
                handle, "SELECT name FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL LIMIT 1",
                -1, &statement, nil
            ) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            try #require(sqlite3_step(statement) == SQLITE_ROW)
            return String(cString: try #require(sqlite3_column_text(statement, 0)))
        }()
        try #require(sqlite3_exec(handle, "DROP INDEX \"\(index)\"", nil, nil, nil) == SQLITE_OK)

        let after = try #require(CoreDataStack.schemaCoherenceKey(storeURL: url, model: model))
        #expect(after != before)
    }

    @Test("the different stores keep separate cache entries")
    func perStoreEntries() throws {
        let (url, model) = try makeClosedStore()
        let defaults = try makeDefaults()
        let key = try #require(CoreDataStack.schemaCoherenceKey(storeURL: url, model: model))
        CoreDataStack.recordSchemaCoherenceVerified(storeURL: url, key: key, defaults: defaults)

        let sibling = url.deletingLastPathComponent().appendingPathComponent("shared.sqlite")
        #expect(!CoreDataStack.isSchemaCoherenceVerified(storeURL: sibling, key: key, defaults: defaults))
    }
}
