import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// MARK: - Schema 25: a schema-24 notebook opens with every record
//
// Schema 25 (plan "Domain logic fixes", Phase 1) adds one private entity,
// `LevelChange`, and ten optional or defaulted attributes: which assignment a
// work copy is of and whether it is the shared row, a child's own three flags
// on her presentation record, the person a guardian row stands for, and the
// classroom's time zone and session days on the shared attendance email
// settings. A notebook written by main's schema-24 build opens with all of
// them the way `CoreDataStack` opens it (`prepareStoresForLoad`, then
// lightweight migration), in both stores, keeping every record.
//
// The schema-24 model is the bundle's with those taken out, in the app's two
// configurations. Its digest is the one main recorded for schema 24
// (`CoreDataSchemaVersionTests.expectedModelDigest` before this change), so
// the stand-in is that model, entity for entity and store for store. Records
// are made and read through KVC: both models are loaded here, so the `CD…`
// classes' own entity lookup is ambiguous.

@Suite("Schema 25 migration", .serialized)
@MainActor
struct Schema25MigrationTests {

    /// `CoreDataStack.modelSchemaDigest` of main's schema-24 model.
    private static let schema24Digest = "2c1528e0e1d8110b5a6db3903573fee53f0da6b953f6595d239ca4003cd2f2e6"
    private static let addedEntity = "LevelChange"
    private static let addedAttributes: [String: Set<String>] = [
        "WorkModel": ["assignmentID", "isSharedRow"],
        "LessonPresentation": ["needsPractice", "needsAnotherPresentation", "manuallyUnblocked"],
        "Guardian": ["personID"],
        "AttendanceEmailSettings": ["classroomTimeZoneID", "sessionFirstDay", "sessionLastDay"]
    ]

    private let studentID = UUID()
    private let workID = UUID()
    private let presentationID = UUID()
    private let guardianID = UUID()
    private let privateSettingsID = UUID()
    private let sharedSettingsID = UUID()

    // MARK: - Fixtures

    private struct TwoStores {
        let directory: URL
        var privateURL: URL { directory.appendingPathComponent("private.sqlite") }
        var sharedURL: URL { directory.appendingPathComponent("shared.sqlite") }
        var urls: [URL] { [privateURL, sharedURL] }
    }

    /// The model as schema 24 had it, with the app's two configurations.
    private func schema24Model() throws -> NSManagedObjectModel {
        let url = try #require(Bundle.main.url(forResource: CoreDataStack.modelName, withExtension: "momd"))
        let loaded = try #require(NSManagedObjectModel(contentsOf: url))
        let model = try #require(loaded.copy() as? NSManagedObjectModel)
        model.entities = model.entities.filter { $0.name != Self.addedEntity }
        for entity in model.entities {
            guard let added = Self.addedAttributes[entity.name ?? ""] else { continue }
            entity.properties = entity.properties.filter { !added.contains($0.name) }
        }
        let shared = model.entities.filter { CoreDataStack.sharedEntityNames.contains($0.name ?? "") }
        let privateOnly = model.entities.filter { CoreDataStack.privateEntityNames.contains($0.name ?? "") }
        model.setEntities(shared, forConfigurationName: CoreDataStack.sharedConfiguration)
        model.setEntities(privateOnly + shared, forConfigurationName: CoreDataStack.privateConfiguration)
        return model
    }

    private func makeDirectory() throws -> TwoStores {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-25-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return TwoStores(directory: directory)
    }

    private func container(_ model: NSManagedObjectModel, stores: TwoStores) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: CoreDataStack.modelName, managedObjectModel: model)
        let privateDescription = CoreDataStack.makeStoreDescription(
            url: stores.privateURL, configuration: CoreDataStack.privateConfiguration
        )
        let sharedDescription = CoreDataStack.makeStoreDescription(
            url: stores.sharedURL, configuration: CoreDataStack.sharedConfiguration
        )
        CoreDataStack.enableHistoryTracking(privateDescription)
        CoreDataStack.enableHistoryTracking(sharedDescription)
        container.persistentStoreDescriptions = [privateDescription, sharedDescription]
        return container
    }

    private func load(_ container: NSPersistentContainer) throws {
        var loadError: Error?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if let loadError { throw loadError }
    }

    private func store(_ configuration: String, of container: NSPersistentContainer) throws -> NSPersistentStore {
        try #require(container.persistentStoreCoordinator.persistentStores.first {
            $0.configurationName == configuration
        })
    }

    private func insert(
        _ entity: String, _ values: [String: Any], into context: NSManagedObjectContext, store: NSPersistentStore
    ) {
        let row = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        for (key, value) in values { row.setValue(value, forKey: key) }
        context.assign(row, to: store)
    }

    private func fetchOne(_ entity: String, id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    /// Both stores as main's schema-24 build left them: a child, her work,
    /// presentation record and guardian in the private store, the email
    /// settings in each, every store stamped 24.
    private func seedSchema24Stores(_ stores: TwoStores) throws {
        try autoreleasepool {
            let old = container(try schema24Model(), stores: stores)
            try load(old)
            let context = old.viewContext
            let privateStore = try store(CoreDataStack.privateConfiguration, of: old)
            let sharedStore = try store(CoreDataStack.sharedConfiguration, of: old)
            insert("Student", ["id": studentID, "firstName": "Ada"], into: context, store: privateStore)
            insert("WorkModel", [
                "id": workID, "title": "Long division", "studentID": studentID.uuidString
            ], into: context, store: privateStore)
            insert("LessonPresentation", [
                "id": presentationID, "studentID": studentID.uuidString, "lessonID": UUID().uuidString
            ], into: context, store: privateStore)
            insert("Guardian", [
                "id": guardianID, "studentID": studentID.uuidString, "name": "A Parent", "email": "parent@example.com"
            ], into: context, store: privateStore)
            insert("AttendanceEmailSettings", [
                "id": privateSettingsID, "toAddresses": "office@example.com"
            ], into: context, store: privateStore)
            insert("AttendanceEmailSettings", [
                "id": sharedSettingsID, "toAddresses": "front@example.com"
            ], into: context, store: sharedStore)
            let coordinator = old.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                var metadata = coordinator.metadata(for: store)
                metadata[CoreDataStack.schemaVersionMetadataKey] = 24
                coordinator.setMetadata(metadata, for: store)
            }
            try context.save()
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
    }

    // MARK: - Tests

    @Test("The stand-in is main's schema-24 model, and schema 25 routes the level history to the private store")
    func standInIsSchema24() throws {
        #expect(CoreDataStack.modelSchemaDigest(try schema24Model()) == Self.schema24Digest)
        let model = try CoreDataStack.sharedModel()
        #expect(CoreDataStack.modelSchemaDigest(model) != Self.schema24Digest)
        let privateNames = Set(model.entities(forConfigurationName: CoreDataStack.privateConfiguration)?
            .compactMap(\.name) ?? [])
        let sharedNames = Set(model.entities(forConfigurationName: CoreDataStack.sharedConfiguration)?
            .compactMap(\.name) ?? [])
        #expect(privateNames.contains(Self.addedEntity))
        #expect(!sharedNames.contains(Self.addedEntity))
        #expect(sharedNames.contains("AttendanceEmailSettings") && privateNames.contains("AttendanceEmailSettings"))
        let levelChange = try #require(model.entitiesByName[Self.addedEntity])
        #expect(levelChange.relationshipsByName.isEmpty)
        #expect(levelChange.uniquenessConstraints.isEmpty)
        for (name, attributes) in Self.addedAttributes {
            let entity = try #require(model.entitiesByName[name])
            for attribute in attributes.sorted() {
                let description = try #require(entity.attributesByName[attribute], "\(name).\(attribute)")
                #expect(
                    description.isOptional || description.defaultValue != nil,
                    "\(name).\(attribute) is neither optional nor defaulted"
                )
            }
        }
    }

    @Test("A schema-24 notebook migrates in both stores, keeps every record, and takes the new fields")
    func schema24StoresMigrate() throws {
        let stores = try makeDirectory()
        let standard = UserDefaults.standard
        let stashedBefore = standard.object(forKey: EnrollmentNoteOwners.defaultsKey)
        defer {
            try? FileManager.default.removeItem(at: stores.directory)
            if let stashedBefore {
                standard.set(stashedBefore, forKey: EnrollmentNoteOwners.defaultsKey)
            } else {
                standard.removeObject(forKey: EnrollmentNoteOwners.defaultsKey)
            }
        }
        try seedSchema24Stores(stores)
        for url in stores.urls {
            #expect(try Self.stamp(at: url) == 24, "\(url.lastPathComponent)")
        }

        let new = try openMigrated(stores)
        let kept = try expectRecordsKept(in: new)
        try expectNewFieldsTakeValues(kept, in: new)

        // Both stores now say schema 25 on disk, so main's schema-24 build
        // refuses them rather than migrating them back.
        for store in new.persistentStoreCoordinator.persistentStores {
            try new.persistentStoreCoordinator.remove(store)
        }
        for url in stores.urls {
            #expect(try Self.stamp(at: url) == CoreDataStack.currentSchemaVersion, "\(url.lastPathComponent)")
        }
        #expect(CoreDataStack.currentSchemaVersion == 25)
    }
}

extension Schema25MigrationTests {

    // MARK: - Steps

    /// The schema-24 records, as the migrated stores hold them.
    private struct Kept {
        let work: NSManagedObject
        let presentation: NSManagedObject
        let guardian: NSManagedObject
        let privateSettings: NSManagedObject
        let sharedSettings: NSManagedObject
    }

    private static func stamp(at url: URL) throws -> Int? {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        return metadata[CoreDataStack.schemaVersionMetadataKey] as? Int
    }

    /// `stores` opened with the current model as `CoreDataStack.init` opens
    /// them: both are seen to need migrating and copied first, then migrated
    /// on load and stamped.
    private func openMigrated(_ stores: TwoStores) throws -> NSPersistentContainer {
        let model = try CoreDataStack.sharedModel()
        let new = container(model, stores: stores)
        for description in new.persistentStoreDescriptions {
            let url = try #require(description.url)
            let migrating = CoreDataStack.storeNeedsMigration(
                storeURL: url, configuration: description.configuration, model: model
            )
            #expect(migrating, "\(url.lastPathComponent) isn't seen to need migrating")
        }
        let copies = try CoreDataStack.prepareStoresForLoad(container: new, model: model)
        #expect(Set(copies.keys) == Set(stores.urls))
        try load(new)
        CoreDataStack.restampSchemaVersion(in: new)
        return new
    }

    /// Every record is still there, in its store, with what it had; the new
    /// fields read as unset (the work flag as false).
    private func expectRecordsKept(in new: NSPersistentContainer) throws -> Kept {
        let context = new.viewContext
        let student = try #require(try fetchOne("Student", id: studentID, in: context), "the child was lost")
        #expect(student.value(forKey: "firstName") as? String == "Ada")
        let work = try #require(try fetchOne("WorkModel", id: workID, in: context), "the work was lost")
        #expect(work.value(forKey: "title") as? String == "Long division")
        #expect(work.value(forKey: "assignmentID") == nil)
        #expect(work.value(forKey: "isSharedRow") as? Bool == false)
        let presentation = try #require(try fetchOne("LessonPresentation", id: presentationID, in: context))
        #expect(presentation.value(forKey: "studentID") as? String == studentID.uuidString)
        for key in ["needsPractice", "needsAnotherPresentation", "manuallyUnblocked"] {
            #expect(presentation.value(forKey: key) == nil, "\(key) is set")
        }
        let guardian = try #require(try fetchOne("Guardian", id: guardianID, in: context), "the guardian was lost")
        #expect(guardian.value(forKey: "email") as? String == "parent@example.com")
        #expect(guardian.value(forKey: "personID") == nil)
        let privateSettings = try #require(try fetchOne("AttendanceEmailSettings", id: privateSettingsID, in: context))
        let sharedSettings = try #require(try fetchOne("AttendanceEmailSettings", id: sharedSettingsID, in: context))
        let privateStore = try store(CoreDataStack.privateConfiguration, of: new)
        let sharedStore = try store(CoreDataStack.sharedConfiguration, of: new)
        #expect(privateSettings.objectID.persistentStore == privateStore)
        #expect(sharedSettings.objectID.persistentStore == sharedStore)
        #expect(sharedSettings.value(forKey: "toAddresses") as? String == "front@example.com")
        for settings in [privateSettings, sharedSettings] {
            for key in ["classroomTimeZoneID", "sessionFirstDay", "sessionLastDay"] {
                #expect(settings.value(forKey: key) == nil, "\(key) is set")
            }
        }
        return Kept(
            work: work, presentation: presentation, guardian: guardian,
            privateSettings: privateSettings, sharedSettings: sharedSettings
        )
    }

    /// The new columns and table take values in both stores, and a level
    /// change goes into the private store.
    private func expectNewFieldsTakeValues(_ kept: Kept, in new: NSPersistentContainer) throws {
        let context = new.viewContext
        let sessionStart = Date(timeIntervalSinceReferenceDate: 810_000_000)
        kept.work.setValue(UUID().uuidString, forKey: "assignmentID")
        kept.work.setValue(true, forKey: "isSharedRow")
        kept.presentation.setValue(false, forKey: "needsPractice")
        kept.presentation.setValue(true, forKey: "manuallyUnblocked")
        kept.guardian.setValue(UUID().uuidString, forKey: "personID")
        kept.sharedSettings.setValue("America/Chicago", forKey: "classroomTimeZoneID")
        kept.sharedSettings.setValue(sessionStart, forKey: "sessionFirstDay")
        kept.privateSettings.setValue(sessionStart, forKey: "sessionLastDay")
        let changeID = UUID()
        let change = NSEntityDescription.insertNewObject(forEntityName: Self.addedEntity, into: context)
        change.setValue(changeID, forKey: "id")
        change.setValue(studentID.uuidString, forKey: "studentID")
        change.setValue("Lower", forKey: "fromLevelRaw")
        change.setValue("Upper", forKey: "toLevelRaw")
        try context.save()
        let privateStore = try store(CoreDataStack.privateConfiguration, of: new)
        #expect(change.objectID.persistentStore == privateStore)

        context.refreshAllObjects()
        let work = try #require(try fetchOne("WorkModel", id: workID, in: context))
        #expect(work.value(forKey: "isSharedRow") as? Bool == true)
        let presentation = try #require(try fetchOne("LessonPresentation", id: presentationID, in: context))
        #expect(presentation.value(forKey: "needsPractice") as? Bool == false)
        #expect(presentation.value(forKey: "needsAnotherPresentation") == nil)
        #expect(presentation.value(forKey: "manuallyUnblocked") as? Bool == true)
        let shared = try #require(try fetchOne("AttendanceEmailSettings", id: sharedSettingsID, in: context))
        #expect(shared.value(forKey: "classroomTimeZoneID") as? String == "America/Chicago")
        #expect(shared.value(forKey: "sessionFirstDay") as? Date == sessionStart)
        let privateSettings = try #require(try fetchOne("AttendanceEmailSettings", id: privateSettingsID, in: context))
        #expect(privateSettings.value(forKey: "sessionLastDay") as? Date == sessionStart)
        let reread = try #require(try fetchOne(Self.addedEntity, id: changeID, in: context))
        #expect(reread.value(forKey: "toLevelRaw") as? String == "Upper")
    }
}
