import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

// MARK: - Schema Version Guard
//
// Two things are being protected here.
//
// 1. `CoreDataStack.currentSchemaVersion` must actually track the model. The
//    app ships a single `.xcdatamodel` that is edited in place, so two builds
//    can both call their model "MariasNotebook 2" while describing different
//    schemas — which is exactly how an Aug-14 archive build came to
//    lightweight-migrate a live `private.sqlite` *backwards* on 2026-08-25,
//    dropping ZGUARDIAN and six ZALBUM* tables. The version stamp is the only
//    trustworthy discriminator, so it must never silently fall behind the
//    model.
//
// 2. The guard itself must refuse newer stores and leave everything else alone.

@Suite("Core Data schema version guard")
@MainActor
final class CoreDataSchemaVersionTests {

    /// SHA-256 over the model's entity version hashes, as of
    /// `CoreDataStack.currentSchemaVersion`.
    ///
    /// When `modelDigestMatchesRecordedSchemaVersion` fails, the model changed.
    /// Bump `CoreDataStack.currentSchemaVersion`, add a line to its version
    /// history, and paste the digest from the failure message here — in that
    /// order. Updating only this constant defeats the guard.
    static let expectedModelDigest = "58371c4a67c192909435c62206bd6f92bc8f9cfd4fc3f73c7b68815987e2214a"

    // MARK: - Version Tracking

    @Test("Model digest still matches the recorded schema version")
    func modelDigestMatchesRecordedSchemaVersion() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let model = stack.container.managedObjectModel
        let digest = CoreDataStack.modelSchemaDigest(model)

        #expect(
            digest == Self.expectedModelDigest,
            """
            The Core Data model changed but CoreDataStack.currentSchemaVersion \
            (\(CoreDataStack.currentSchemaVersion)) was not bumped.

            An older build that shares this store — an installed copy, an \
            .xcarchive, another checkout — will otherwise migrate the store \
            backwards and drop the tables it doesn't know about.

            Bump currentSchemaVersion, then set expectedModelDigest to:
            \(digest)
            """
        )
    }

    @Test("Schema digest is stable across repeated loads of the same model")
    func digestIsStable() throws {
        let first = CoreDataStack.modelSchemaDigest(
            try CoreDataTestHelpers.makeInMemoryStack().container.managedObjectModel
        )
        let second = CoreDataStack.modelSchemaDigest(
            try CoreDataTestHelpers.makeInMemoryStack().container.managedObjectModel
        )
        #expect(first == second, "Digest must not depend on load order or dictionary iteration")
    }

    // MARK: - Guard Behaviour

    @Test("A store stamped by a newer build is refused")
    func refusesStoreFromNewerBuild() throws {
        let store = try TemporaryStore()
        defer { store.cleanUp() }
        try store.writeSchemaStamp(CoreDataStack.currentSchemaVersion + 1)

        #expect(throws: CoreDataStackError.self) {
            try CoreDataStack.verifyStoreIsNotFromNewerBuild(storeURL: store.url)
        }
    }

    @Test("A store stamped by this build or an older one is allowed")
    func allowsSameOrOlderStore() throws {
        let store = try TemporaryStore()
        defer { store.cleanUp() }

        try store.writeSchemaStamp(CoreDataStack.currentSchemaVersion)
        try CoreDataStack.verifyStoreIsNotFromNewerBuild(storeURL: store.url)

        try store.writeSchemaStamp(CoreDataStack.currentSchemaVersion - 1)
        try CoreDataStack.verifyStoreIsNotFromNewerBuild(storeURL: store.url)
    }

    @Test("An unstamped store predates the guard and is allowed through")
    func allowsUnstampedStore() throws {
        let store = try TemporaryStore()
        defer { store.cleanUp() }
        #expect(store.readSchemaStamp() == nil)
        try CoreDataStack.verifyStoreIsNotFromNewerBuild(storeURL: store.url)
    }

    @Test("A missing store file is allowed through")
    func allowsMissingStore() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).sqlite")
        try CoreDataStack.verifyStoreIsNotFromNewerBuild(storeURL: url)
    }

    // MARK: - Stamping

    @Test("Stamping records the current version and preserves existing metadata")
    func stampingWritesTheVersionAndKeepsMetadata() throws {
        let store = try TemporaryStore()
        defer { store.cleanUp() }

        let before = try store.readMetadata()
        let uuidBefore = before[NSStoreUUIDKey] as? String

        CoreDataStack.stampSchemaVersion(storeURL: store.url)

        #expect(store.readSchemaStamp() == CoreDataStack.currentSchemaVersion)
        let after = try store.readMetadata()
        #expect(after[NSStoreUUIDKey] as? String == uuidBefore, "Stamping must not rewrite Core Data's own metadata")
        #expect(after[NSStoreModelVersionHashesKey] != nil, "Model version hashes must survive stamping")
    }

    @Test("Stamping a store this build already stamped is a no-op it tolerates")
    func stampingIsIdempotent() throws {
        let store = try TemporaryStore()
        defer { store.cleanUp() }

        CoreDataStack.stampSchemaVersion(storeURL: store.url)
        CoreDataStack.stampSchemaVersion(storeURL: store.url)
        #expect(store.readSchemaStamp() == CoreDataStack.currentSchemaVersion)
    }

    @Test("A store this build stamps is then accepted by the guard")
    func stampedStoreRoundTripsThroughTheGuard() throws {
        let store = try TemporaryStore()
        defer { store.cleanUp() }

        CoreDataStack.stampSchemaVersion(storeURL: store.url)
        try CoreDataStack.verifyStoreIsNotFromNewerBuild(storeURL: store.url)
    }

    // MARK: - Stack Integration

    @Test("Opening a store stamps it, so a later build can tell it is not older")
    func openingAStoreStampsIt() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SchemaVersionStack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("local.sqlite")

        _ = try CoreDataStack(enableCloudKit: false, inMemory: false, localStoreURL: storeURL)

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: storeURL
        )
        #expect(metadata[CoreDataStack.schemaVersionMetadataKey] as? Int == CoreDataStack.currentSchemaVersion)
    }

    @Test("A stack refuses to open a store stamped by a newer build")
    func stackRefusesStoreFromNewerBuild() throws {
        let store = try TemporaryStore()
        defer { store.cleanUp() }
        try store.writeSchemaStamp(CoreDataStack.currentSchemaVersion + 1)

        // Must throw *before* Core Data gets the chance to infer a reverse
        // mapping and drop the tables this build does not know about.
        #expect(throws: CoreDataStackError.self) {
            _ = try CoreDataStack(enableCloudKit: false, inMemory: false, localStoreURL: store.url)
        }
    }
}

// MARK: - Test Support

/// A throwaway on-disk SQLite store with a one-entity model, created and then
/// closed so the metadata class methods can operate on the file.
private struct TemporaryStore {
    let directory: URL
    let url: URL

    init() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SchemaVersionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("test.sqlite")

        let attribute = NSAttributeDescription()
        attribute.name = "title"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = true

        let entity = NSEntityDescription()
        entity.name = "Thing"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [attribute]

        let model = NSManagedObjectModel()
        model.entities = [entity]

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
        try coordinator.remove(store)
    }

    func readMetadata() throws -> [String: Any] {
        try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
    }

    func readSchemaStamp() -> Int? {
        (try? readMetadata())?[CoreDataStack.schemaVersionMetadataKey] as? Int
    }

    func writeSchemaStamp(_ version: Int) throws {
        var metadata = try readMetadata()
        metadata[CoreDataStack.schemaVersionMetadataKey] = version
        try NSPersistentStoreCoordinator.setMetadata(metadata, type: .sqlite, at: url)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
