import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Hunt of 2026-10-05: #14 a store about to migrate was stamped with this
// build's format before the migration ran, so one whose migration failed
// claimed a format it didn't have; #16 after a failed load the pre-migration
// backup was copied back over a store the coordinator still had open, file by
// file; #45 the schema digest didn't see an entity moving between the stores.

@Suite("Opening the stores safely", .serialized)
@MainActor
struct StoreLoadSafetyTests {

    // MARK: - #14 Stamp timing

    @Test("A store about to migrate isn't stamped before it loads, and is once it has")
    func migratingStoreStampedAfterLoad() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let url = try StoreFileFixture.makeStore(
            at: fixture.url("thing.sqlite"), model: StoreFileFixture.model(), rows: 2
        )
        let newer = StoreFileFixture.model(withNote: true)
        let container = StoreFileFixture.container(model: newer, url: url)

        try CoreDataStack.prepareStoresForLoad(container: container, model: newer)
        #expect(StoreFileFixture.stamp(at: url) == nil, "not before the migration has run")

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        #expect(loadError == nil)
        CoreDataStack.restampSchemaVersion(in: container)
        #expect(StoreFileFixture.stamp(at: url) == CoreDataStack.currentSchemaVersion)
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    @Test("A store about to migrate is backed up first, with all its rows")
    func migratingStoreIsBackedUp() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let url = try StoreFileFixture.makeStore(
            at: fixture.url("thing.sqlite"), model: StoreFileFixture.model(), rows: 3
        )
        // The launch's case: the newer model, with its migration options.
        let newer = StoreFileFixture.model(withNote: true)
        let container = StoreFileFixture.container(model: newer, url: url)

        let backups = try CoreDataStack.prepareStoresForLoad(container: container, model: newer)

        let backup = try #require(backups[url], "a migrating store gets a backup before it migrates")
        #expect(StoreFileFixture.rowCount(at: backup) == 3)
        #expect(StoreFileFixture.stamp(at: url) == nil, "and the store itself is still unmigrated")
    }

    @Test("A store that needn't migrate is still stamped before it loads")
    func currentStoreStampedBeforeLoad() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let model = StoreFileFixture.model()
        let url = try StoreFileFixture.makeStore(at: fixture.url("thing.sqlite"), model: model, rows: 1)

        let container = StoreFileFixture.container(model: model, url: url)
        try CoreDataStack.prepareStoresForLoad(container: container, model: model)
        #expect(StoreFileFixture.stamp(at: url) == CoreDataStack.currentSchemaVersion)
    }

    // MARK: - #16 Rolling back a failed load

    @Test("A failed load closes every open store before the backup goes back")
    func rollbackClosesStoresFirst() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let model = StoreFileFixture.model()
        let url = try StoreFileFixture.makeStore(at: fixture.url("thing.sqlite"), model: model, rows: 2)
        let backup = try #require(CoreDataStack.backUpStoreBeforeMigration(storeURL: url, model: model))
        #expect(StoreFileFixture.rowCount(at: backup) == 2)

        // The store loaded (and changed) in this coordinator while its sibling failed.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        _ = try coordinator.addPersistentStore(type: .sqlite, at: url)
        try StoreFileFixture.addRows(3, to: coordinator, model: model)

        let restored = CoreDataStack.rollBackFailedLoad(
            coordinator: coordinator, backups: [url: backup], model: model, options: [:]
        )

        #expect(restored)
        #expect(coordinator.persistentStores.isEmpty, "nothing left open under the restored file")
        #expect(StoreFileFixture.rowCount(at: url) == 2, "back to the bytes before the attempt")
    }

    @Test("The pre-migration backup holds what was only in the store's journal")
    func backupIncludesTheJournal() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let model = StoreFileFixture.model()
        let url = fixture.url("thing.sqlite")
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
        try StoreFileFixture.addRows(4, to: coordinator, model: model)

        // Still open, so the rows may sit only in the WAL.
        let backup = try #require(CoreDataStack.backUpStoreBeforeMigration(storeURL: url, model: model))
        try coordinator.remove(store)
        #expect(StoreFileFixture.rowCount(at: backup) == 4)
    }

    // MARK: - #45 The digest sees which store an entity lives in

    @Test("Moving an entity between the stores changes the schema digest")
    func digestCoversConfigurations() {
        func model(sharedHoldsThing: Bool) -> NSManagedObjectModel {
            let model = StoreFileFixture.model()
            let entities = model.entities
            model.setEntities(sharedHoldsThing ? entities : [], forConfigurationName: CoreDataStack.sharedConfiguration)
            model.setEntities(entities, forConfigurationName: CoreDataStack.privateConfiguration)
            return model
        }
        let inShare = CoreDataStack.modelSchemaDigest(model(sharedHoldsThing: true))
        let privateOnly = CoreDataStack.modelSchemaDigest(model(sharedHoldsThing: false))
        #expect(inShare != privateOnly)
        #expect(inShare == CoreDataStack.modelSchemaDigest(model(sharedHoldsThing: true)))
    }

    // MARK: - A store Core Data emptied (2026-10-10)

    // The Assistant's sample class emptied its store with
    // `destroyPersistentStore` each new day. On iOS 26 the pre-load checks'
    // metadata read wrote Core Data's bookkeeping tables into the empty file,
    // and the load then failed ("Can't find table for entity …"). iOS 27 and
    // macOS 27 leave the file alone, so here this pins the rule rather than
    // reproducing the failure.

    @Test("A store Core Data emptied is left untouched before it loads, and loads as a new one")
    func emptiedStoreLoadsFresh() throws {
        let fixture = try StoreFileFixture()
        defer { fixture.cleanUp() }
        let model = StoreFileFixture.model()
        let url = try StoreFileFixture.makeStore(at: fixture.url("thing.sqlite"), model: model, rows: 2)
        try NSPersistentStoreCoordinator(managedObjectModel: model)
            .destroyPersistentStore(at: url, type: .sqlite, options: nil)
        #expect(CoreDataStack.isUnbuiltStore(storeURL: url))

        let container = StoreFileFixture.container(model: model, url: url)
        let backups = try CoreDataStack.prepareStoresForLoad(container: container, model: model)
        #expect(backups.isEmpty, "nothing to back up")
        #expect(CoreDataStack.isUnbuiltStore(storeURL: url), "no tables written into it")

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        #expect(loadError == nil)
        try StoreFileFixture.addRows(1, to: container.persistentStoreCoordinator, model: model)
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        #expect(StoreFileFixture.rowCount(at: url) == 1)
        #expect(!CoreDataStack.isUnbuiltStore(storeURL: url))
    }
}
