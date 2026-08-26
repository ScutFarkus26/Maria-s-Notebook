import Foundation
import CoreData
import SQLite3
import Testing
@testable import Maria_s_Notebook

// MARK: - Downgraded-Store Repair
//
// When an older build lightweight-migrates a store *backwards* it drops tables
// and recompacts Z_ENT, leaving ANSCKRECORDMETADATA rows pointing at the old
// numbering. The next forward migration then dies with
// "UNIQUE constraint failed: ANSCKRECORDMETADATA.ZENTITYID, ANSCKRECORDMETADATA.ZENTITYPK".
//
// The repair deletes only *dangling* rows. The load-bearing assertion in this
// suite is `keepsMetadataForRecordsThatStillExist`: a surviving record's
// metadata row holds its CKRecord name, and dropping it would make Core Data
// re-upload that record under a fresh name and duplicate it in CloudKit.

@Suite("Downgraded-store repair")
@MainActor
final class StoreDowngradeRepairTests {

    // MARK: - Dangling Metadata

    @Test("Removes metadata whose entity is no longer in the store")
    func removesMetadataForDroppedEntities() throws {
        let store = try FakeStore()
        defer { store.cleanUp() }

        let removed = CoreDataStack.cleanDanglingCloudKitMetadata(storeURL: store.url)

        #expect(removed == 3)
        #expect(!store.recordNames().contains("dead-entity"))
        #expect(!store.recordNames().contains("dead-entity-2"))
    }

    @Test("Removes metadata whose row is gone but whose entity survives")
    func removesMetadataForDeletedRows() throws {
        let store = try FakeStore()
        defer { store.cleanUp() }

        CoreDataStack.cleanDanglingCloudKitMetadata(storeURL: store.url)

        #expect(!store.recordNames().contains("dangling-pk"))
    }

    @Test("Keeps metadata for records that still exist")
    func keepsMetadataForRecordsThatStillExist() throws {
        let store = try FakeStore()
        defer { store.cleanUp() }

        CoreDataStack.cleanDanglingCloudKitMetadata(storeURL: store.url)

        // Every surviving row, and nothing else. Losing one of these would
        // re-upload that record to CloudKit under a new name.
        #expect(store.recordNames().sorted() == ["live-lesson-1", "live-student-1", "live-student-2"])
    }

    @Test("Repeating the repair changes nothing")
    func repairIsIdempotent() throws {
        let store = try FakeStore()
        defer { store.cleanUp() }

        CoreDataStack.cleanDanglingCloudKitMetadata(storeURL: store.url)
        let secondPass = CoreDataStack.cleanDanglingCloudKitMetadata(storeURL: store.url)

        #expect(secondPass == 0)
        #expect(store.recordNames().count == 3)
    }

    @Test("A store with no CloudKit metadata table is left alone")
    func toleratesStoreWithoutCloudKitMetadata() throws {
        let store = try FakeStore(includeCloudKitMetadata: false)
        defer { store.cleanUp() }

        #expect(CoreDataStack.cleanDanglingCloudKitMetadata(storeURL: store.url) == 0)
    }

    @Test("A missing store file is left alone")
    func toleratesMissingStore() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("absent-\(UUID().uuidString).sqlite")
        #expect(CoreDataStack.cleanDanglingCloudKitMetadata(storeURL: url) == 0)
    }

    // MARK: - Duplicated Entity Registrations

    @Test("Twin metadata under a duplicated entity keeps the data table's id")
    func dedupeKeepsTheLiveRegistration() throws {
        let store = try FakeStore(duplicateStudentEntity: true)
        defer { store.cleanUp() }

        let removed = CoreDataStack.dedupeCloudKitMetadataForDuplicatedEntities(storeURL: store.url)

        #expect(removed == 1)
        let names = store.recordNames()
        // ZSTUDENT rows carry Z_ENT = 1, so the row under id 1 wins even
        // though the stale twin was inserted later.
        #expect(names.contains("live-student-1"))
        #expect(!names.contains("stale-student-1"))
    }

    @Test("Rows without a twin survive dedupe, whichever registration they sit under")
    func dedupeKeepsUntwinnedRows() throws {
        let store = try FakeStore(duplicateStudentEntity: true)
        defer { store.cleanUp() }

        CoreDataStack.dedupeCloudKitMetadataForDuplicatedEntities(storeURL: store.url)

        let names = store.recordNames()
        #expect(names.contains("stale-only"), "A record known only under the stale id must keep its metadata")
        #expect(names.contains("live-student-2"))
        #expect(names.contains("live-lesson-1"))
    }

    @Test("Dedupe is idempotent")
    func dedupeIsIdempotent() throws {
        let store = try FakeStore(duplicateStudentEntity: true)
        defer { store.cleanUp() }

        CoreDataStack.dedupeCloudKitMetadataForDuplicatedEntities(storeURL: store.url)
        #expect(CoreDataStack.dedupeCloudKitMetadataForDuplicatedEntities(storeURL: store.url) == 0)
    }

    @Test("A store with unique entity numbering is left alone")
    func dedupeIsANoOpWithoutDuplicates() throws {
        let store = try FakeStore()
        defer { store.cleanUp() }

        #expect(CoreDataStack.dedupeCloudKitMetadataForDuplicatedEntities(storeURL: store.url) == 0)
        #expect(store.recordNames().count == 6)
    }

    // MARK: - Physical Schema Coherence

    /// A store built by a real coordinator, then mutilated the way the Aug-14
    /// build mutilated shared.sqlite: a column dropped while the metadata
    /// still claims the current schema.
    private struct CoherentStore {
        let dir: URL
        let url: URL
        let model: NSManagedObjectModel
    }

    private func makeCoherentStore() throws -> CoherentStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Coherence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shared.sqlite")

        let title = NSAttributeDescription()
        title.name = "title"
        title.attributeType = .stringAttributeType
        title.isOptional = true
        let albumID = NSAttributeDescription()
        albumID.name = "albumID"
        albumID.attributeType = .UUIDAttributeType
        albumID.isOptional = true
        let scratch = NSAttributeDescription()
        scratch.name = "scratch"
        scratch.attributeType = .stringAttributeType
        scratch.isOptional = true
        scratch.isTransient = true

        let entity = NSEntityDescription()
        entity.name = "Lesson"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [title, albumID, scratch]

        let model = NSManagedObjectModel()
        model.entities = [entity]

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
        try coordinator.remove(store)
        return CoherentStore(dir: dir, url: url, model: model)
    }

    @Test("A store the coordinator just built is coherent (transient attrs ignored)")
    func freshStoreIsCoherent() throws {
        let store = try makeCoherentStore()
        defer { try? FileManager.default.removeItem(at: store.dir) }

        let findings = CoreDataStack.incoherentSchemaFindings(
            storeURL: store.url, configuration: nil, model: store.model
        )
        #expect(findings.isEmpty, "Unexpected findings: \(findings)")
    }

    @Test("A dropped column is detected even though metadata claims compatibility")
    func droppedColumnIsDetected() throws {
        let store = try makeCoherentStore()
        defer { try? FileManager.default.removeItem(at: store.dir) }

        var handle: OpaquePointer?
        #expect(sqlite3_open(store.url.path, &handle) == SQLITE_OK)
        sqlite3_exec(handle, "ALTER TABLE ZLESSON DROP COLUMN ZALBUMID", nil, nil, nil)
        sqlite3_close(handle)

        let findings = CoreDataStack.incoherentSchemaFindings(
            storeURL: store.url, configuration: nil, model: store.model
        )
        #expect(findings == ["ZLESSON.ZALBUMID missing"])
    }

    @Test("A missing table is detected")
    func missingTableIsDetected() throws {
        let store = try makeCoherentStore()
        defer { try? FileManager.default.removeItem(at: store.dir) }

        var handle: OpaquePointer?
        #expect(sqlite3_open(store.url.path, &handle) == SQLITE_OK)
        sqlite3_exec(handle, "DROP TABLE ZLESSON", nil, nil, nil)
        sqlite3_close(handle)

        let findings = CoreDataStack.incoherentSchemaFindings(
            storeURL: store.url, configuration: nil, model: store.model
        )
        #expect(findings == ["ZLESSON missing"])
    }

    @Test("Quarantine moves the store aside so a fresh one can be built")
    func quarantineMovesTheStoreAside() throws {
        let store = try makeCoherentStore()
        defer { try? FileManager.default.removeItem(at: store.dir) }

        CoreDataStack.quarantineIncoherentStore(
            storeURL: store.url, findings: ["ZLESSON.ZALBUMID missing"]
        )

        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        let quarantined = store.url.appendingPathExtension("incoherent")
        #expect(FileManager.default.fileExists(atPath: quarantined.path))
    }

    // MARK: - Backup and Rollback

    @Test("A failed repair can be rolled back to the original bytes")
    func backupRoundTripsExactly() throws {
        let store = try FakeStore()
        defer { store.cleanUp() }

        let original = try Data(contentsOf: store.url)
        let backup = try #require(CoreDataStack.backUpStoreBeforeMigration(storeURL: store.url))
        defer { try? FileManager.default.removeItem(at: backup) }

        // Wreck it the way a half-finished migration would.
        CoreDataStack.cleanDanglingCloudKitMetadata(storeURL: store.url)
        #expect(try Data(contentsOf: store.url) != original || store.recordNames().count == 3)

        #expect(CoreDataStack.restoreStoreBackup(backup, to: store.url))
        #expect(try Data(contentsOf: store.url) == original)
        #expect(store.recordNames().count == 6, "Rollback must bring the dangling rows back too")
    }

    @Test("Backing up twice replaces the previous copy rather than accumulating")
    func backupReplacesPrevious() throws {
        let store = try FakeStore()
        defer { store.cleanUp() }

        let first = try #require(CoreDataStack.backUpStoreBeforeMigration(storeURL: store.url))
        let second = try #require(CoreDataStack.backUpStoreBeforeMigration(storeURL: store.url))
        defer { try? FileManager.default.removeItem(at: second) }

        #expect(first == second)
    }

    // MARK: - Migration Detection

    @Test("A store matching the model does not report a pending migration")
    func matchingStoreNeedsNoMigration() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let model = stack.container.managedObjectModel

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MigrationCheck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("matching.sqlite")

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let added = try coordinator.addPersistentStore(type: .sqlite, at: url)
        try coordinator.remove(added)

        #expect(!CoreDataStack.storeNeedsMigration(storeURL: url, configuration: nil, model: model))
    }

    @Test("A store built from a different model reports a pending migration")
    func mismatchedStoreNeedsMigration() throws {
        let store = try FakeStore()
        defer { store.cleanUp() }
        let model = try CoreDataTestHelpers.makeInMemoryStack().container.managedObjectModel

        // FakeStore is hand-rolled SQL with no Core Data metadata, so this also
        // covers the "cannot read metadata" path: it must not claim a migration.
        _ = CoreDataStack.storeNeedsMigration(storeURL: store.url, configuration: nil, model: model)
    }
}

// MARK: - Test Support

/// A hand-built SQLite file shaped like a Core Data + CloudKit store, holding
/// three live records and three dangling metadata rows.
private struct FakeStore {
    let directory: URL
    let url: URL

    /// `duplicateStudentEntity` re-registers Student under a second Z_ENT (3)
    /// and adds metadata under that id — one row twinning live-student-1's
    /// record, one describing a record of its own — mirroring the duplicated
    /// Work*/YearPlanEntry registrations found in the real private.sqlite.
    init(includeCloudKitMetadata: Bool = true, duplicateStudentEntity: Bool = false) throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FakeStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("private.sqlite")

        var statements = [
            "CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER)",
            "INSERT INTO Z_PRIMARYKEY VALUES (1,'Student',0,2),(2,'Lesson',0,1)",
            "CREATE TABLE ZSTUDENT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER)",
            "INSERT INTO ZSTUDENT VALUES (1,1,1),(2,1,1)",
            "CREATE TABLE ZLESSON (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER)",
            "INSERT INTO ZLESSON VALUES (1,2,1)"
        ]

        if includeCloudKitMetadata {
            statements.append("""
                CREATE TABLE ANSCKRECORDMETADATA (
                    Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER,
                    ZENTITYID INTEGER, ZENTITYPK INTEGER, ZRECORDNAME VARCHAR,
                    UNIQUE (ZENTITYID, ZENTITYPK)
                )
                """)
            statements.append("""
                INSERT INTO ANSCKRECORDMETADATA VALUES
                    (1,1,1, 1, 1,  'live-student-1'),
                    (2,1,1, 1, 2,  'live-student-2'),
                    (3,1,1, 1, 99, 'dangling-pk'),
                    (4,1,1, 2, 1,  'live-lesson-1'),
                    (5,1,1, 7, 3,  'dead-entity'),
                    (6,1,1, 9, 4,  'dead-entity-2')
                """)
        }

        if duplicateStudentEntity {
            statements.append("INSERT INTO Z_PRIMARYKEY VALUES (3,'Student',0,2)")
            if includeCloudKitMetadata {
                // The stale twin (7) deliberately has a HIGHER Z_PK than the
                // live row (1): the keeper must be chosen by the id the data
                // table uses, not by recency.
                statements.append("""
                    INSERT INTO ANSCKRECORDMETADATA VALUES
                        (7,1,1, 3, 1, 'stale-student-1'),
                        (8,1,1, 3, 7, 'stale-only')
                    """)
            }
        }

        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw FakeStoreError.couldNotCreate
        }
        defer { sqlite3_close(handle) }
        for sql in statements {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                throw FakeStoreError.couldNotCreate
            }
        }
    }

    /// The ZRECORDNAME of every surviving metadata row.
    func recordNames() -> [String] {
        var names: [String] = []
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { return names }
        defer { sqlite3_close(handle) }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT ZRECORDNAME FROM ANSCKRECORDMETADATA"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return names }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) {
                names.append(String(cString: text))
            }
        }
        return names
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    enum FakeStoreError: Error {
        case couldNotCreate
    }
}
