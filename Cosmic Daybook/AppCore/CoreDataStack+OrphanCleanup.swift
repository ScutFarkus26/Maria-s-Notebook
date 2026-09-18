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

// MARK: - Downgraded-Store Repair
//
// The mirror image of `cleanOrphanEntityMetadata`. That function handles
// entities present in the *store* but missing from the *model* — the normal
// "we dropped an entity" direction. This handles the opposite: a store that an
// older build migrated *backwards*, dropping tables and recompacting `Z_ENT`
// while leaving ANSCKRECORDMETADATA rows pointing at the old numbering. The
// next forward migration then dies with
//
//     UNIQUE constraint failed: ANSCKRECORDMETADATA.ZENTITYID, ANSCKRECORDMETADATA.ZENTITYPK
//     reason=constraint violation during attempted migration
//
// because two metadata rows remap onto the same (entity, row) pair.
//
// Only *dangling* rows are deleted — ones whose record no longer exists in the
// store. Metadata for a record that is still present is left strictly alone:
// it holds that record's CKRecord name, and discarding it would make Core Data
// re-upload the record under a fresh name and duplicate it in CloudKit.

extension CoreDataStack {

    /// True when `storeURL`'s recorded model hashes differ from `model`'s, i.e.
    /// opening it will trigger a migration. Used to keep the backup and repair
    /// work below off the normal launch path entirely.
    /// `configuration` must be the store's own configuration name — a split
    /// store only ever holds that configuration's entities, so comparing it
    /// against the whole model would report "needs migration" every launch.
    static func storeNeedsMigration(
        storeURL: URL,
        configuration: String?,
        model: NSManagedObjectModel
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }
        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                type: .sqlite,
                at: storeURL
            )
            return !model.isConfiguration(withName: configuration, compatibleWithStoreMetadata: metadata)
        } catch {
            // Unreadable metadata is its own failure; let the store load report it.
            return false
        }
    }

    /// Copies `storeURL` (and its `-wal`/`-shm` companions) alongside itself
    /// before a migration runs, replacing any previous backup of that store.
    ///
    /// Migration is in-place and irreversible, and the repair below edits the
    /// file. One rollback copy is the difference between "retry something else"
    /// and "restore from a week-old backup". Returns the backup base URL, or
    /// `nil` if the copy could not be made — in which case the caller must not
    /// attempt any repair.
    static func backUpStoreBeforeMigration(storeURL: URL) -> URL? {
        let backupURL = storeURL.deletingPathExtension()
            .appendingPathExtension("premigration.sqlite")
        do {
            try removeStoreFiles(at: backupURL)
            for suffix in storeFileSuffixes {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try FileManager.default.copyItem(
                    at: source,
                    to: URL(fileURLWithPath: backupURL.path + suffix)
                )
            }
            cleanupLogger.info(
                "Backed up \(storeURL.lastPathComponent, privacy: .public) before migration"
            )
            return backupURL
        } catch {
            let msg = "Could not back up \(storeURL.lastPathComponent) before migration: " +
                "\(error.localizedDescription)"
            cleanupLogger.error("\(msg, privacy: .public)")
            try? removeStoreFiles(at: backupURL)
            return nil
        }
    }

    /// Puts a backup made by ``backUpStoreBeforeMigration(storeURL:)`` back in
    /// place. Used when a repaired store still fails to load, so a failed
    /// recovery attempt never leaves the user worse off than before it ran.
    @discardableResult
    static func restoreStoreBackup(_ backupURL: URL, to storeURL: URL) -> Bool {
        do {
            try removeStoreFiles(at: storeURL)
            for suffix in storeFileSuffixes {
                let source = URL(fileURLWithPath: backupURL.path + suffix)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try FileManager.default.copyItem(
                    at: source,
                    to: URL(fileURLWithPath: storeURL.path + suffix)
                )
            }
            cleanupLogger.warning(
                "Restored \(storeURL.lastPathComponent, privacy: .public) from its pre-migration backup"
            )
            return true
        } catch {
            let msg = "CRITICAL: could not restore \(storeURL.lastPathComponent) from backup at " +
                "\(backupURL.path): \(error.localizedDescription)"
            cleanupLogger.fault("\(msg, privacy: .public)")
            return false
        }
    }

    /// Deletes ANSCKRECORDMETADATA rows whose record no longer exists.
    ///
    /// Returns the number of rows removed, or 0 when the store has no CloudKit
    /// metadata table or nothing dangling.
    @discardableResult
    static func cleanDanglingCloudKitMetadata(storeURL: URL) -> Int {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return 0 }

        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK, let db else {
            cleanupLogger.warning(
                "Could not open \(storeURL.lastPathComponent, privacy: .public) for CloudKit metadata repair"
            )
            if db != nil { sqlite3_close(db) }
            return 0
        }
        defer { sqlite3_close(db) }

        guard tableExists(db: db, name: "ANSCKRECORDMETADATA") else { return 0 }

        let liveEntities = Dictionary(
            uniqueKeysWithValues: readPrimaryKeyEntities(db: db).map { ($0.zEnt, $0.name) }
        )

        var deleted = 0
        execute(db: db, "BEGIN TRANSACTION")
        for entityID in distinctMetadataEntityIDs(db: db) {
            guard let name = liveEntities[entityID] else {
                // The entity this metadata describes is not in the store at all.
                deleted += deleteMetadata(db: db, where: "ZENTITYID = \(entityID)")
                continue
            }
            let table = "Z\(name.uppercased())"
            guard tableExists(db: db, name: table) else {
                deleted += deleteMetadata(db: db, where: "ZENTITYID = \(entityID)")
                continue
            }
            // Keep every row whose record still exists; drop the rest.
            deleted += deleteMetadata(
                db: db,
                where: "ZENTITYID = \(entityID) AND ZENTITYPK NOT IN (SELECT Z_PK FROM \"\(table)\")"
            )
        }
        execute(db: db, "COMMIT")

        if deleted > 0 {
            let msg = "Removed \(deleted) dangling CloudKit metadata row(s) from " +
                "\(storeURL.lastPathComponent) so migration can proceed"
            cleanupLogger.warning("\(msg, privacy: .public)")
        }
        return deleted
    }

    // MARK: - Helpers

    /// SQLite writes a store as three files; all of them move together.
    private static var storeFileSuffixes: [String] { ["", "-wal", "-shm"] }

    private static func removeStoreFiles(at baseURL: URL) throws {
        for suffix in storeFileSuffixes {
            let url = URL(fileURLWithPath: baseURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func distinctMetadataEntityIDs(db: OpaquePointer) -> [Int64] {
        var ids: [Int64] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT DISTINCT ZENTITYID FROM ANSCKRECORDMETADATA"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return ids }
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.append(sqlite3_column_int64(stmt, 0))
        }
        return ids
    }

    private static func deleteMetadata(db: OpaquePointer, where clause: String) -> Int {
        execute(db: db, "DELETE FROM ANSCKRECORDMETADATA WHERE \(clause)")
        return Int(sqlite3_changes(db))
    }
}

// MARK: - Migration Diagnostics

extension CoreDataStack {

    /// Logs the structural facts needed to diagnose a migration that dies on
    /// `UNIQUE constraint failed: ANSCKRECORDMETADATA.ZENTITYID, ZENTITYPK`.
    ///
    /// Schema, counts, and entity numbering only — never record contents. The
    /// numbering is the interesting part: adding entities whose names sort
    /// early (`AlbumBookmark`, `Guardian`, …) shifts `Z_ENT` for everything
    /// after them, and Core Data renumbers `ZENTITYID` in place against a
    /// uniqueness constraint that the half-finished renumbering violates.
    static func logCloudKitMetadataShape(storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        var handle: OpaquePointer?
        guard sqlite3_open(storeURL.path, &handle) == SQLITE_OK, let handle else {
            if handle != nil { sqlite3_close(handle) }
            return
        }
        defer { sqlite3_close(handle) }
        guard tableExists(db: handle, name: "ANSCKRECORDMETADATA") else { return }

        let name = storeURL.lastPathComponent
        for ddl in queryStrings(db: handle, sql: """
            SELECT sql FROM sqlite_master
            WHERE tbl_name = 'ANSCKRECORDMETADATA' AND sql IS NOT NULL
            """) {
            cleanupLogger.warning("\(name, privacy: .public) DDL: \(ddl, privacy: .public)")
        }

        let counts = queryStrings(db: handle, sql: """
            SELECT 'rows=' || COUNT(*) || ' distinctEntities=' || COUNT(DISTINCT ZENTITYID)
            FROM ANSCKRECORDMETADATA
            """)
        for line in counts {
            cleanupLogger.warning("\(name, privacy: .public) metadata \(line, privacy: .public)")
        }

        let numbering = readPrimaryKeyEntities(db: handle)
            .sorted { $0.zEnt < $1.zEnt }
            .map { "\($0.zEnt):\($0.name)" }
            .joined(separator: " ")
        cleanupLogger.warning("\(name, privacy: .public) Z_PRIMARYKEY \(numbering, privacy: .public)")
    }

    private static func queryStrings(db: OpaquePointer, sql: String) -> [String] {
        var results: [String] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return results }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: text))
            }
        }
        return results
    }
}

// MARK: - Duplicated Entity Registrations

extension CoreDataStack {

    /// Collapses ANSCKRECORDMETADATA twins in a store whose `Z_PRIMARYKEY`
    /// registers the same entity name under two `Z_ENT` ids — the scar of an
    /// old re-registration. (Danny's `private.sqlite` lists WorkModel,
    /// WorkStep, WorkParticipantEntity, WorkCompletionRecord and YearPlanEntry
    /// twice: as 71/74–77 and again as 78/81–84.)
    ///
    /// Migration maps source `Z_ENT` ids to destination ids *by name*, so both
    /// registrations collapse onto one destination id — and two metadata rows
    /// that describe the same record under the two source ids collide on the
    /// store's `UNIQUE (ZENTITYID, ZENTITYPK)` index the moment they are
    /// renumbered: "Cannot migrate store in-place: constraint violation during
    /// attempted migration". Deleting *dangling* rows cannot fix this; the
    /// colliding rows all describe records that still exist.
    ///
    /// For each record with twins, the row kept is the one under the id the
    /// entity's data table actually uses — that is the linkage CloudKit
    /// exports have been maintaining — falling back to the newest row. Rows
    /// without a twin are untouched, whichever registration they sit under.
    @discardableResult
    static func dedupeCloudKitMetadataForDuplicatedEntities(storeURL: URL) -> Int {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return 0 }

        var handle: OpaquePointer?
        guard sqlite3_open(storeURL.path, &handle) == SQLITE_OK, let handle else {
            if handle != nil { sqlite3_close(handle) }
            return 0
        }
        defer { sqlite3_close(handle) }
        guard tableExists(db: handle, name: "ANSCKRECORDMETADATA") else { return 0 }

        var idsByName: [String: [Int64]] = [:]
        for entry in readPrimaryKeyEntities(db: handle) {
            idsByName[entry.name, default: []].append(entry.zEnt)
        }
        let duplicated = idsByName.filter { $0.value.count > 1 }
        guard !duplicated.isEmpty else { return 0 }

        let name = storeURL.lastPathComponent
        let dupList = duplicated.keys.sorted().joined(separator: ", ")
        cleanupLogger.warning(
            "\(name, privacy: .public) registers duplicated entities in Z_PRIMARYKEY: \(dupList, privacy: .public)"
        )

        var doomedRowIDs: [Int64] = []
        for (entityName, ids) in duplicated {
            let liveID = modalDataTableEntityID(db: handle, entityName: entityName)
            for rows in metadataRowsByRecord(db: handle, entityIDs: ids).values where rows.count > 1 {
                // `UNIQUE (ZENTITYID, ZENTITYPK)` guarantees at most one row per
                // id, so "under the live id" can only match a single row.
                let keeper = rows.first { $0.entityID == liveID }
                    ?? rows.max { $0.rowID < $1.rowID }!
                doomedRowIDs += rows.filter { $0.rowID != keeper.rowID }.map(\.rowID)
            }
        }
        guard !doomedRowIDs.isEmpty else { return 0 }

        execute(db: handle, "BEGIN TRANSACTION")
        for chunk in stride(from: 0, to: doomedRowIDs.count, by: 500) {
            let slice = doomedRowIDs[chunk..<min(chunk + 500, doomedRowIDs.count)]
            let list = slice.map(String.init).joined(separator: ",")
            execute(db: handle, "DELETE FROM ANSCKRECORDMETADATA WHERE Z_PK IN (\(list))")
        }
        execute(db: handle, "COMMIT")

        let msg = "Collapsed \(doomedRowIDs.count) twin CloudKit metadata row(s) in \(name) " +
            "so entity renumbering cannot collide"
        cleanupLogger.warning("\(msg, privacy: .public)")
        return doomedRowIDs.count
    }

    /// The `Z_ENT` value the entity's data table rows actually carry (the most
    /// common one, if a mix survives). `nil` when the table is missing or empty.
    private static func modalDataTableEntityID(db: OpaquePointer, entityName: String) -> Int64? {
        let table = "Z\(entityName.uppercased())"
        guard tableExists(db: db, name: table) else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT Z_ENT FROM \"\(table)\" GROUP BY Z_ENT ORDER BY COUNT(*) DESC LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    /// Metadata rows under any of `entityIDs`, grouped by the record they
    /// describe (`ZENTITYPK`).
    private static func metadataRowsByRecord(
        db: OpaquePointer,
        entityIDs: [Int64]
    ) -> [Int64: [(rowID: Int64, entityID: Int64)]] {
        var rowsByRecord: [Int64: [(rowID: Int64, entityID: Int64)]] = [:]
        let list = entityIDs.map(String.init).joined(separator: ",")
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT Z_PK, ZENTITYID, ZENTITYPK FROM ANSCKRECORDMETADATA WHERE ZENTITYID IN (\(list))"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return rowsByRecord }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let recordPK = sqlite3_column_int64(stmt, 2)
            rowsByRecord[recordPK, default: []].append(
                (rowID: sqlite3_column_int64(stmt, 0), entityID: sqlite3_column_int64(stmt, 1))
            )
        }
        return rowsByRecord
    }
}

// MARK: - Physical Schema Coherence

extension CoreDataStack {

    /// Columns the model requires that the store file physically lacks, or
    /// `[]` for a healthy store.
    ///
    /// Store *metadata* can lie. On 2026-08-26, shared.sqlite's recorded
    /// version hashes claimed compatibility with the current model while its
    /// ZLESSON table had no ZALBUMID column — a scar left by an older build's
    /// half-completed backwards migration. Core Data trusts the hashes, so it
    /// loads such a store without migrating, and then every fetch that touches
    /// the missing column fails at runtime with "no such column" (26,595 times
    /// in the first 12 minutes of one session). This check compares the model
    /// against the actual `PRAGMA table_info` schema instead.
    ///
    /// Conservative on purpose — only *missing* tables and columns count.
    /// Extra columns and tables are normal leftovers. Transient, derived, and
    /// composite attributes have no plain column and are skipped, as are
    /// child entities (their columns live in their root entity's table).
    static func incoherentSchemaFindings(
        storeURL: URL,
        configuration: String?,
        model: NSManagedObjectModel
    ) -> [String] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }

        var handle: OpaquePointer?
        guard sqlite3_open(storeURL.path, &handle) == SQLITE_OK, let handle else {
            if handle != nil { sqlite3_close(handle) }
            return []
        }
        defer { sqlite3_close(handle) }

        // An empty file that SQLite happily "opens" is a store Core Data has
        // not built yet, not an incoherent one.
        guard tableExists(db: handle, name: "Z_PRIMARYKEY") else { return [] }

        let entities: [NSEntityDescription]
        if let configuration, let configured = model.entities(forConfigurationName: configuration) {
            entities = configured
        } else {
            entities = model.entities
        }

        var findings: [String] = []
        for entity in entities where entity.superentity == nil {
            guard let entityName = entity.name else { continue }
            let table = "Z\(entityName.uppercased())"
            guard tableExists(db: handle, name: table) else {
                findings.append("\(table) missing")
                continue
            }
            let columns = tableColumns(db: handle, table: table)
            findings += missingColumns(of: entity, table: table, existing: columns)
        }
        return findings
    }

    /// The plain-column attributes of `entity` that `existing` lacks.
    private static func missingColumns(
        of entity: NSEntityDescription,
        table: String,
        existing: Set<String>
    ) -> [String] {
        entity.attributesByName.compactMap { attributeName, attribute in
            guard !attribute.isTransient else { return nil }
            let kind = String(describing: type(of: attribute))
            guard !kind.contains("Derived"), !kind.contains("Composite") else { return nil }
            let column = "Z\(attributeName.uppercased())"
            return existing.contains(column) ? nil : "\(table).\(column) missing"
        }
    }

    /// Moves an incoherent store's files aside (as `<name>.incoherent`,
    /// replacing any earlier quarantine) so `loadPersistentStores` builds a
    /// fresh, fully-schemad store at the original URL.
    ///
    /// Reserved for the **shared** store, which is a local mirror of the
    /// CloudKit shared database — after the rebuild, CloudKit re-imports its
    /// contents, so nothing is lost. The private store must never take this
    /// path; an incoherent private store is surfaced as an error instead.
    static func quarantineIncoherentStore(storeURL: URL, findings: [String]) {
        let list = findings.sorted().joined(separator: ", ")
        let msg = "\(storeURL.lastPathComponent) physical schema does not match its metadata " +
            "(\(list)) — quarantining so a fresh store can be rebuilt from CloudKit"
        cleanupLogger.fault("\(msg, privacy: .public)")

        let quarantineURL = storeURL.appendingPathExtension("incoherent")
        do {
            try removeStoreFiles(at: quarantineURL)
            for suffix in storeFileSuffixes {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try FileManager.default.moveItem(
                    at: source,
                    to: URL(fileURLWithPath: quarantineURL.path + suffix)
                )
            }
        } catch {
            let failMsg = "Could not quarantine \(storeURL.lastPathComponent): \(error.localizedDescription)"
            cleanupLogger.fault("\(failMsg, privacy: .public)")
        }
    }

    private static func tableColumns(db: OpaquePointer, table: String) -> Set<String> {
        var columns: Set<String> = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\"\(table)\")", -1, &stmt, nil) == SQLITE_OK else {
            return columns
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 1) {
                columns.insert(String(cString: text))
            }
        }
        return columns
    }
}
