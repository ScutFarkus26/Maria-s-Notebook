import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// MARK: - Schema 20 migration: Schedules joins the share
//
// Schema 20 added four entities (`TimetableLane`, `TimetableBlock`,
// `TimetableChange`, `TimetableBooking`) to both configurations. Every store on
// a device was written with the schema-19 shape. These open both with the new
// model the way `CoreDataStack` does, and check that what was there stays and
// that each store now takes the new rows.
//
// Objects are made with `insertNewObject(forEntityName:)` and read through
// KVC: the schema-19 stand-in and the bundle's model are both loaded here.

@Suite("Schedules migration", .serialized)
@MainActor
struct TimetableMigrationTests {

    private static let schedulesTypes: Set<String> = [
        "TimetableLane", "TimetableBlock", "TimetableChange", "TimetableBooking"
    ]

    /// The model as schema 19 had it: no Schedules types, in either store.
    private func schema19Model() throws -> NSManagedObjectModel {
        let url = try #require(Bundle.main.url(forResource: CoreDataStack.modelName, withExtension: "momd"))
        let loaded = try #require(NSManagedObjectModel(contentsOf: url))
        let model = try #require(loaded.copy() as? NSManagedObjectModel)
        model.entities = model.entities.filter { !Self.schedulesTypes.contains($0.name ?? "") }
        for entity in model.entities {
            // Plain objects: the bundle's model keeps the CD… classes to itself.
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        let shared = CoreDataStack.sharedEntityNames.subtracting(Self.schedulesTypes)
        let routed = CoreDataStack.privateEntityNames.union(shared)
        model.setEntities(
            model.entities.filter { shared.contains($0.name ?? "") },
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

    @Test("The model's two configurations both hold the four Schedules types")
    func configurations() throws {
        let model = try CoreDataStack.sharedModel()
        for configuration in [CoreDataStack.sharedConfiguration, CoreDataStack.privateConfiguration] {
            let names = Set((model.entities(forConfigurationName: configuration) ?? []).compactMap(\.name))
            #expect(Self.schedulesTypes.isSubset(of: names), "\(configuration)")
        }
        // Schema 20 brought them; later schemas still have them.
        #expect(CoreDataStack.currentSchemaVersion >= 20)
    }

    @Test("Schema-19 stores open with schema 20: what was there stays, and both stores take Schedules rows")
    func schema19StoresMigrate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("schedules-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 1. Schema 19: a child in the guide's private store, and a name as it
        //    reaches an assistant's shared store.
        try autoreleasepool {
            let old = container(try schema19Model(), in: directory)
            try load(old)
            let context = old.viewContext
            let student = NSEntityDescription.insertNewObject(forEntityName: "Student", into: context)
            student.setValue(UUID(), forKey: "id")
            student.setValue("Maya", forKey: "firstName")
            context.assign(student, to: try store(CoreDataStack.privateConfiguration, of: old))
            let person = NSEntityDescription.insertNewObject(forEntityName: "ClassroomPerson", into: context)
            person.setValue(UUID(), forKey: "id")
            context.assign(person, to: try store(CoreDataStack.sharedConfiguration, of: old))
            try context.save()
            for store in old.persistentStoreCoordinator.persistentStores {
                try old.persistentStoreCoordinator.remove(store)
            }
        }

        // 2. Schema 20, prepared exactly as `CoreDataStack.init` prepares it.
        let model = try CoreDataStack.sharedModel()
        let new = container(model, in: directory)
        try CoreDataStack.prepareStoresForLoad(container: new, model: model)
        try load(new)
        let context = new.viewContext
        let privateStore = try store(CoreDataStack.privateConfiguration, of: new)
        let sharedStore = try store(CoreDataStack.sharedConfiguration, of: new)

        // 3. What was there stays where it was.
        #expect(try count("Student", in: privateStore, context) == 1)
        #expect(try count("ClassroomPerson", in: sharedStore, context) == 1)

        // 4. The guide's rows go in his private store; an assistant's phone
        //    receives them in its shared one.
        var rows: [(NSManagedObject, NSPersistentStore)] = []
        for name in Self.schedulesTypes.sorted() {
            for target in [privateStore, sharedStore] {
                let row = NSEntityDescription.insertNewObject(forEntityName: name, into: context)
                row.setValue(UUID(), forKey: "id")
                context.assign(row, to: target)
                rows.append((row, target))
            }
        }
        try context.save()
        #expect(rows.count == 8)
        for (row, target) in rows {
            #expect(row.objectID.persistentStore == target)
        }
        let lane = try #require(rows.first { $0.0.entity.name == "TimetableLane" }?.0)
        #expect(lane.value(forKey: "kindRaw") as? String == "room")
        let block = try #require(rows.first { $0.0.entity.name == "TimetableBlock" }?.0)
        #expect(block.value(forKey: "lengthMinutes") as? Int64 == 30)
        let booking = try #require(rows.first { $0.0.entity.name == "TimetableBooking" }?.0)
        #expect(booking.value(forKey: "minute") as? Int64 == -1, "no set time unless one is given")
    }
}
