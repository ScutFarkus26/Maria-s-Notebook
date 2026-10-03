import CoreData
import Foundation
import OSLog
import SQLite3

// MARK: - Stale Primary-Key Counters
//
// Core Data hands out each table's `Z_PK` from a counter in `Z_PRIMARYKEY`
// (`Z_MAX`), read when the store opens and advanced on every save. It never
// checks the table itself. If `Z_MAX` sits below a `Z_PK` that is already in
// use, the next insert lands on an occupied key and the save fails with
// `NSCocoaErrorDomain 133020 "Could not merge changes"` (verified on macOS
// 27, 2026-09-08: three consecutive inserts into a store with a rewound
// counter all failed, and each failure moved the counter on by exactly one).
// The store heals itself one failed save at a time, which for a run of 818
// occupied keys is 818 failed saves.
//
// Danny's `private.sqlite` copy of 2026-09-08 19:23 had exactly this shape
// for five entities: WorkModel (counter 6363, rows up to 6541), WorkCheckIn,
// TodoItem, ProjectSession and YearPlanEntry (counter 13209, every key from
// 13210 to 14027 occupied). The rows above the counter were months old while
// newer rows sat below it, so two key sequences had coexisted in one file —
// the residue of a store-level merge, not something Core Data itself does.
// How it arose is not settled; what matters is that raising the counter is
// always safe. A higher counter only skips keys, and gaps in `Z_PK` are
// normal after any delete.

extension CoreDataStack {
    private static let primaryKeyLogger = Logger.coreDataPrimaryKeyRepair

    /// One counter that was behind its table, and where it was moved to.
    struct RaisedPrimaryKeyCounter: Equatable {
        let entityName: String
        let previousMax: Int64
        let newMax: Int64
    }

    /// Raises every `Z_PRIMARYKEY.Z_MAX` that is below the highest `Z_PK`
    /// actually present in that entity's table.
    ///
    /// Runs before the store is opened, so Core Data reads the corrected
    /// counter. Entities whose table cannot be found are left alone; a
    /// counter that is already at or above its table is untouched. Idempotent
    /// and cheap — one `MAX(Z_PK)` per table.
    @discardableResult
    static func raiseStalePrimaryKeyCounters(storeURL: URL) -> [RaisedPrimaryKeyCounter] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }

        var handle: OpaquePointer?
        guard sqlite3_open(storeURL.path, &handle) == SQLITE_OK, let handle else {
            primaryKeyLogger.warning(
                "Could not open \(storeURL.lastPathComponent, privacy: .public) for primary-key repair"
            )
            if handle != nil { sqlite3_close(handle) }
            return []
        }
        defer { sqlite3_close(handle) }
        guard tableExists(db: handle, name: "Z_PRIMARYKEY") else { return [] }

        var raised: [RaisedPrimaryKeyCounter] = []
        for counter in readPrimaryKeyCounters(db: handle) {
            guard let table = dataTable(for: counter.name, db: handle),
                  let highest = highestPrimaryKey(in: table, db: handle),
                  highest > counter.max else { continue }
            raised.append(RaisedPrimaryKeyCounter(
                entityName: counter.name, previousMax: counter.max, newMax: highest
            ))
        }
        guard !raised.isEmpty else { return [] }

        execute(db: handle, "BEGIN TRANSACTION")
        for entry in raised {
            execute(
                db: handle,
                "UPDATE Z_PRIMARYKEY SET Z_MAX = \(entry.newMax) "
                    + "WHERE Z_NAME = '\(entry.entityName)' AND Z_MAX < \(entry.newMax)"
            )
        }
        execute(db: handle, "COMMIT")

        let summary = raised
            .map { "\($0.entityName) \($0.previousMax)→\($0.newMax)" }
            .joined(separator: ", ")
        let msg = "Raised \(raised.count) stale primary-key counter(s) in \(storeURL.lastPathComponent): \(summary)"
        primaryKeyLogger.warning("\(msg, privacy: .public)")
        return raised
    }

    // MARK: - Helpers

    /// The table an entity's rows live in. App entities use `Z<NAME>`; the
    /// CloudKit mirroring and history entities use `A<NAME>`.
    private static func dataTable(for entityName: String, db: OpaquePointer) -> String? {
        let upper = entityName.uppercased()
        for candidate in ["Z\(upper)", "A\(upper)"] where tableExists(db: db, name: candidate) {
            return candidate
        }
        return nil
    }

    private static func highestPrimaryKey(in table: String, db: OpaquePointer) -> Int64? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT MAX(Z_PK) FROM \"\(table)\""
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW,
              sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    private static func readPrimaryKeyCounters(db: OpaquePointer) -> [(name: String, max: Int64)] {
        var results: [(String, Int64)] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT Z_NAME, Z_MAX FROM Z_PRIMARYKEY", -1, &stmt, nil) == SQLITE_OK else {
            return results
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cstr = sqlite3_column_text(stmt, 0) else { continue }
            results.append((String(cString: cstr), sqlite3_column_int64(stmt, 1)))
        }
        return results
    }

    private static func tableExists(db: OpaquePointer, name: String) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(name)'"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private static func execute(db: OpaquePointer, _ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK, let errMsg {
            let msg = String(cString: errMsg)
            primaryKeyLogger.warning("SQLite exec failed (\(sql, privacy: .public)): \(msg, privacy: .public)")
            sqlite3_free(errMsg)
        }
    }
}
