import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// MARK: - Schema 16 migration: the classroom's list of names joins the share
//
// Schema 16 added `ClassroomPerson` to both configurations. Every store on a
// device was written with the schema-15 shape: the guide's `private.sqlite`
// holds the classroom, and `shared.sqlite` (an assistant's class, or the
// guide's own, empty) has no table for names. These open both with the new
// model the way `CoreDataStack` does and check that what was there stays and
// that each store now takes a person's row.
//
// Objects are made with `insertNewObject(forEntityName:)` and read through
// KVC: the schema-15 stand-in and the bundle's model are both loaded here.

@Suite("Classroom names migration", .serialized)
@MainActor
struct ClassroomPersonMigrationTests {

    /// The model as schema 15 had it: no `ClassroomPerson`, in either store.
    private func schema15Model() throws -> NSManagedObjectModel {
        let url = try #require(Bundle.main.url(forResource: CoreDataStack.modelName, withExtension: "momd"))
        let loaded = try #require(NSManagedObjectModel(contentsOf: url))
        let model = try #require(loaded.copy() as? NSManagedObjectModel)
        model.entities = model.entities.filter { $0.name != "ClassroomPerson" }
        for entity in model.entities {
            // Plain objects: the bundle's model keeps the CD… classes to itself.
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        let routed = CoreDataStack.privateEntityNames.union(CoreDataStack.sharedEntityNames)
        model.setEntities(
            model.entities.filter { CoreDataStack.sharedEntityNames.contains($0.name ?? "") },
            forConfigurationName: CoreDataStack.sharedConfiguration
        )
        model.setEntities(
            model.entities.filter { routed.contains($0.name ?? "") },
            forConfigurationName: CoreDataStack.privateConfiguration
        )
        return model
    }

    private func container(_ model: NSManagedObjectModel, in directory: URL) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: CoreDataStack.modelName, managedObjectModel: model)
        container.persistentStoreDescriptions = [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration]
            .map { configuration in
                let description = CoreDataStack.makeStoreDescription(
                    url: directory.appendingPathComponent("\(configuration).sqlite"), configuration: configuration
                )
                CoreDataStack.enableHistoryTracking(description)
                return description
            }
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

    private func count(
        _ entityName: String, in store: NSPersistentStore, _ context: NSManagedObjectContext
    ) throws -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.affectedStores = [store]
        return try context.count(for: request)
    }

    @Test("Schema-15 stores open with schema 16: what was there stays, and both stores take names")
    func schema15StoresMigrate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("classroom-names-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 1. Schema 15: a child in the guide's private store, and the front-desk
        //    settings as they reach an assistant's shared store.
        try autoreleasepool {
            let old = container(try schema15Model(), in: directory)
            try load(old)
            let context = old.viewContext
            let student = NSEntityDescription.insertNewObject(forEntityName: "Student", into: context)
            student.setValue(UUID(), forKey: "id")
            student.setValue("Maya", forKey: "firstName")
            context.assign(student, to: try store(CoreDataStack.privateConfiguration, of: old))
            let settings = NSEntityDescription.insertNewObject(forEntityName: "AttendanceEmailSettings", into: context)
            settings.setValue(UUID(), forKey: "id")
            context.assign(settings, to: try store(CoreDataStack.sharedConfiguration, of: old))
            try context.save()
            for store in old.persistentStoreCoordinator.persistentStores {
                try old.persistentStoreCoordinator.remove(store)
            }
        }

        // 2. Schema 16, prepared exactly as `CoreDataStack.init` prepares it.
        let model = try CoreDataStack.sharedModel()
        let new = container(model, in: directory)
        try CoreDataStack.prepareStoresForLoad(container: new, model: model)
        try load(new)
        let context = new.viewContext
        let privateStore = try store(CoreDataStack.privateConfiguration, of: new)
        let sharedStore = try store(CoreDataStack.sharedConfiguration, of: new)

        // 3. What was there stays where it was.
        #expect(try count("Student", in: privateStore, context) == 1)
        #expect(try count("AttendanceEmailSettings", in: sharedStore, context) == 1)

        // 4. The guide's row goes in his private store, an assistant's in her shared one.
        var rows: [(NSManagedObject, NSPersistentStore)] = []
        for (recordName, target) in [("_guide", privateStore), ("_ana", sharedStore)] {
            let row = NSEntityDescription.insertNewObject(forEntityName: "ClassroomPerson", into: context)
            row.setValue(UUID(), forKey: "id")
            row.setValue(recordName, forKey: "recordName")
            row.setValue("A name", forKey: "displayName")
            context.assign(row, to: target)
            rows.append((row, target))
        }
        try context.save()
        for (row, target) in rows {
            #expect(row.objectID.persistentStore == target)
            #expect(row.value(forKey: "roleRaw") as? String == "assistant", "the default never claims the guide")
        }
    }
}
