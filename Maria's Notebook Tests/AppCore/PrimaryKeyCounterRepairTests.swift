import Foundation
import CoreData
import SQLite3
import Testing
@testable import Maria_s_Notebook

// MARK: - Stale Primary-Key Counter Repair
//
// Core Data reads `Z_PRIMARYKEY.Z_MAX` when a store opens and hands out the
// next `Z_PK` from it without checking the table. A counter that sits below
// an occupied key makes the next save fail with "Could not merge changes".
// The repair raises such counters to the table's real maximum before the
// store opens. Raising can only skip keys, so the load-bearing assertions
// here are that healthy counters are never touched and that a raise is
// exact rather than generous.

@Suite("Stale primary-key counter repair")
@MainActor
final class PrimaryKeyCounterRepairTests {

    @Test("Raises a counter that sits below occupied keys")
    func raisesStaleCounter() throws {
        let store = try CounterStore(
            counters: ["WorkModel": 6363, "Student": 2],
            keys: ["ZWORKMODEL": [6240, 6350, 6365, 6541], "ZSTUDENT": [1, 2]]
        )
        defer { store.cleanUp() }

        let raised = CoreDataStack.raiseStalePrimaryKeyCounters(storeURL: store.url)

        #expect(raised == [
            .init(entityName: "WorkModel", previousMax: 6363, newMax: 6541)
        ])
        #expect(store.counter("WorkModel") == 6541)
        #expect(store.counter("Student") == 2)
    }

    @Test("A counter ahead of its table is left where it is")
    func leavesHealthyCounterAlone() throws {
        // Deleted rows leave the counter above the highest surviving key;
        // pulling it back down would reissue those keys.
        let store = try CounterStore(
            counters: ["Student": 10],
            keys: ["ZSTUDENT": [1, 2, 3]]
        )
        defer { store.cleanUp() }

        #expect(CoreDataStack.raiseStalePrimaryKeyCounters(storeURL: store.url).isEmpty)
        #expect(store.counter("Student") == 10)
    }

    @Test("CloudKit mirroring tables under the A-prefix are covered too")
    func coversMirroringTables() throws {
        let store = try CounterStore(
            counters: ["NSCKRecordMetadata": 5],
            keys: ["ANSCKRECORDMETADATA": [1, 9]]
        )
        defer { store.cleanUp() }

        let raised = CoreDataStack.raiseStalePrimaryKeyCounters(storeURL: store.url)
        #expect(raised.map(\.newMax) == [9])
        #expect(store.counter("NSCKRecordMetadata") == 9)
    }

    @Test("An entity without a table, or with an empty one, is skipped")
    func skipsMissingAndEmptyTables() throws {
        let store = try CounterStore(
            counters: ["Ghost": 0, "Empty": 4],
            keys: ["ZEMPTY": []]
        )
        defer { store.cleanUp() }

        #expect(CoreDataStack.raiseStalePrimaryKeyCounters(storeURL: store.url).isEmpty)
        #expect(store.counter("Empty") == 4)
    }

    @Test("Repeating the repair changes nothing")
    func repairIsIdempotent() throws {
        let store = try CounterStore(
            counters: ["WorkModel": 1],
            keys: ["ZWORKMODEL": [1, 2, 3]]
        )
        defer { store.cleanUp() }

        CoreDataStack.raiseStalePrimaryKeyCounters(storeURL: store.url)
        #expect(CoreDataStack.raiseStalePrimaryKeyCounters(storeURL: store.url).isEmpty)
        #expect(store.counter("WorkModel") == 3)
    }

    @Test("A missing store file is left alone")
    func toleratesMissingStore() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("no-such-store-\(UUID().uuidString).sqlite")
        #expect(CoreDataStack.raiseStalePrimaryKeyCounters(storeURL: url).isEmpty)
    }
}

// MARK: - Test Support

/// A hand-built SQLite file carrying only the parts of a Core Data store the
/// repair reads: `Z_PRIMARYKEY` and the data tables' `Z_PK` columns.
private struct CounterStore {
    let directory: URL
    let url: URL

    init(counters: [String: Int64], keys: [String: [Int64]]) throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CounterStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("private.sqlite")

        var statements = [
            "CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER)"
        ]
        for (index, (name, max)) in counters.sorted(by: { $0.key < $1.key }).enumerated() {
            statements.append("INSERT INTO Z_PRIMARYKEY VALUES (\(index + 1),'\(name)',0,\(max))")
        }
        for (table, pks) in keys {
            statements.append("CREATE TABLE \(table) (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER)")
            for pk in pks {
                statements.append("INSERT INTO \(table) VALUES (\(pk),1,1)")
            }
        }

        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw CounterStoreError.couldNotCreate
        }
        defer { sqlite3_close(handle) }
        for sql in statements {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                throw CounterStoreError.couldNotCreate
            }
        }
    }

    func counter(_ entityName: String) -> Int64? {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { return nil }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = '\(entityName)'"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    enum CounterStoreError: Error {
        case couldNotCreate
    }
}
