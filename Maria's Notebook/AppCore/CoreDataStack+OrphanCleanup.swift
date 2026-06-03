import CoreData
import Foundation
import OSLog
import SQLite3

extension CoreDataStack {
    private static let cleanupLogger = Logger.app(category: "CoreDataOrphanCleanup")

    /// Prepares an on-disk store so NSPersistentCloudKitContainer's lightweight migration
    /// can succeed after entities have been removed from the model.
    ///
    /// Two failure modes are handled:
    ///
    /// 1. `UNIQUE constraint failed: ANSCKRECORDMETADATA.ZENTITYID, ZENTITYPK` —
    ///    raised when migration touches ANSCKRECORDMETADATA rows that point at a
    ///    dropped entity's Z_ENT id. We pre-delete those rows.
    ///
    /// 2. `no such table: ZFOO` — raised when an earlier cleanup pass (or a partial
    ///    migration) dropped an orphan entity's data table, but Core Data's next
    ///    migration still tries to `DROP TABLE ZFOO` because the store metadata
    ///    still lists the entity. We recreate a minimal empty stub so the drop
    ///    succeeds. Leaving Z_PRIMARYKEY entries alone is fine — Core Data removes
    ///    them as part of its own migration.
    ///
    /// Safe no-op if the store doesn't exist (first install).
    static func cleanOrphanEntityMetadata(
        storeURL: URL,
        model: NSManagedObjectModel
    ) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let modelEntities = Set(model.entities.compactMap(\.name))
        let storedEntities = readEntitiesFromStoreMetadata(storeURL: storeURL)
        let orphanNames = storedEntities.subtracting(modelEntities)
        guard !orphanNames.isEmpty else { return }

        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK, let db else {
            cleanupLogger.warning("Could not open \(storeURL.lastPathComponent, privacy: .public) for orphan cleanup")
            if db != nil { sqlite3_close(db) }
            return
        }
        defer { sqlite3_close(db) }

        cleanupLogger.info(
            "Preparing \(storeURL.lastPathComponent, privacy: .public) for migration. Orphan entities: \(orphanNames.sorted().joined(separator: ", "), privacy: .public)"
        )

        // Map orphan name -> Z_ENT id from Z_PRIMARYKEY (if still present there)
        let zEntByName = Dictionary(
            uniqueKeysWithValues: readPrimaryKeyEntities(db: db).map { ($0.name, $0.zEnt) }
        )

        let hasCloudKitMetadata = tableExists(db: db, name: "ANSCKRECORDMETADATA")

        execute(db: db, "BEGIN TRANSACTION")
        for name in orphanNames {
            // 1. Clear CloudKit metadata rows so the UNIQUE-constraint migration step doesn't fire
            if hasCloudKitMetadata, let zEnt = zEntByName[name] {
                execute(db: db, "DELETE FROM ANSCKRECORDMETADATA WHERE ZENTITYID = \(zEnt)")
            }

            // 2. Ensure the data table exists so Core Data's DROP TABLE step has something to drop
            let tableName = "Z\(name.uppercased())"
            if !tableExists(db: db, name: tableName) {
                cleanupLogger.info(
                    "Recreating empty stub table \(tableName, privacy: .public) so Core Data migration can drop it"
                )
                execute(
                    db: db,
                    "CREATE TABLE \"\(tableName)\" (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER)"
                )
            }
        }
        execute(db: db, "COMMIT")

        cleanupLogger.info("Orphan cleanup complete for \(storeURL.lastPathComponent, privacy: .public)")
    }

    /// Reads the set of entity names recorded in the store's `Z_METADATA` plist
    /// (specifically `NSStoreModelVersionHashes`). These are the entities the
    /// store thinks it has on disk — i.e. the source model for the upcoming migration.
    private static func readEntitiesFromStoreMetadata(storeURL: URL) -> Set<String> {
        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                type: .sqlite,
                at: storeURL
            )
            if let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any] {
                return Set(hashes.keys)
            }
        } catch {
            cleanupLogger.warning(
                "Could not read store metadata for \(storeURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
        return []
    }

    private static func tableExists(db: OpaquePointer, name: String) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(name)'"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private static func readPrimaryKeyEntities(db: OpaquePointer) -> [(zEnt: Int64, name: String)] {
        var results: [(Int64, String)] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY", -1, &stmt, nil) == SQLITE_OK else {
            return results
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let zEnt = sqlite3_column_int64(stmt, 0)
            guard let cstr = sqlite3_column_text(stmt, 1) else { continue }
            results.append((zEnt, String(cString: cstr)))
        }
        return results
    }

    private static func execute(db: OpaquePointer, _ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK, let errMsg {
            let msg = String(cString: errMsg)
            cleanupLogger.warning("SQLite exec failed (\(sql, privacy: .public)): \(msg, privacy: .public)")
            sqlite3_free(errMsg)
        }
    }
}
