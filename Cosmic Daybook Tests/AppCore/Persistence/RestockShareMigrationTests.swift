import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// MARK: - Schema 15 migration: Restock joins the classroom share
//
// Schema 15 moved Supply, SupplyTransaction and OrderItem into the Shared
// configuration and gave Supply and OrderItem new attributes. Every store on
// a device was written with the schema-14 shape: the guide's `private.sqlite`
// holds the supplies and orders, and `shared.sqlite` (an assistant's, or the
// guide's own, empty) has no tables for them. These open both with the new
// model the way `CoreDataStack` does and check that the guide's rows keep
// everything, read as the defaults say, and that the shared store now takes
// all three types.
//
// Objects are made with `insertNewObject(forEntityName:)` and read through
// KVC: the schema-14 stand-in and the bundle's model are both loaded here.

@Suite("Restock share migration", .serialized)
@MainActor
struct RestockShareMigrationTests {

    /// `CoreDataStack.sharedEntityNames` as schema 14 had it.
    private static let schema14SharedNames: Set<String> = [
        "Student", "AttendanceRecord", "NonSchoolDay", "SchoolDayOverride", "AttendanceDayLock",
        "AttendanceEmailSend", "AttendanceEmailSettings"
    ]
    private static let schema15Attributes: [String: Set<String>] = [
        "Supply": ["levelRaw", "sourceRaw", "urlString", "levelChangedAt", "levelChangedByID", "levelChangedByName"],
        "OrderItem": ["sourceRaw", "supplyID", "addedByID", "addedByName"]
    ]

    /// The model as schema 14 had it: no Restock attributes, and the
    /// seven-type Shared configuration.
    private func schema14Model() throws -> NSManagedObjectModel {
        let url = try #require(Bundle.main.url(forResource: CoreDataStack.modelName, withExtension: "momd"))
        let loaded = try #require(NSManagedObjectModel(contentsOf: url))
        let model = try #require(loaded.copy() as? NSManagedObjectModel)
        for entity in model.entities {
            // Plain objects: the bundle's model keeps the CD… classes to itself.
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            guard let later = Self.schema15Attributes[entity.name ?? ""] else { continue }
            entity.properties = entity.properties.filter { !later.contains($0.name) }
        }
        let routed = CoreDataStack.privateEntityNames.union(CoreDataStack.sharedEntityNames)
        model.setEntities(
            model.entities.filter { Self.schema14SharedNames.contains($0.name ?? "") },
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

    private func fetch(_ entityName: String, id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    /// A paper-towel staple with one line of history, and an order, in the
    /// guide's private store as schema 14 wrote them.
    private func seedSchema14(in directory: URL, supplyID: UUID, transactionID: UUID, orderID: UUID) throws {
        try autoreleasepool {
            let old = container(try schema14Model(), in: directory)
            try load(old)
            let context = old.viewContext
            let privateStore = try store(CoreDataStack.privateConfiguration, of: old)
            let supply = NSEntityDescription.insertNewObject(forEntityName: "Supply", into: context)
            supply.setValue(supplyID, forKey: "id")
            supply.setValue("Paper Towels", forKey: "name")
            supply.setValue(Int64(0), forKey: "currentQuantity")
            let transaction = NSEntityDescription.insertNewObject(forEntityName: "SupplyTransaction", into: context)
            transaction.setValue(transactionID, forKey: "id")
            transaction.setValue(supplyID.uuidString, forKey: "supplyID")
            transaction.setValue(supply, forKey: "supply")
            let order = NSEntityDescription.insertNewObject(forEntityName: "OrderItem", into: context)
            order.setValue(orderID, forKey: "id")
            order.setValue("https://www.amazon.com/dp/B0B2MMB4LJ", forKey: "urlString")
            for row in [supply, transaction, order] { context.assign(row, to: privateStore) }
            try context.save()
            for store in old.persistentStoreCoordinator.persistentStores {
                try old.persistentStoreCoordinator.remove(store)
            }
        }
    }

    @Test("Schema-14 stores open with schema 15: the guide's rows stay, and the shared store takes Restock")
    func schema14StoresMigrate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("restock-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let supplyID = UUID(), transactionID = UUID(), orderID = UUID()

        // 1. Schema 14: the live shelf's shape in the guide's private store.
        try seedSchema14(in: directory, supplyID: supplyID, transactionID: transactionID, orderID: orderID)

        // 2. Schema 15, prepared exactly as `CoreDataStack.init` prepares it.
        let model = try CoreDataStack.sharedModel()
        let new = container(model, in: directory)
        try CoreDataStack.prepareStoresForLoad(container: new, model: model)
        try load(new)
        let context = new.viewContext
        let privateStore = try store(CoreDataStack.privateConfiguration, of: new)
        let sharedStore = try store(CoreDataStack.sharedConfiguration, of: new)

        // 3. The guide's rows are where they were, reading as the defaults say.
        let supply = try #require(try fetch("Supply", id: supplyID, in: context))
        #expect(supply.objectID.persistentStore == privateStore)
        #expect(supply.value(forKey: "levelRaw") as? String == "stocked")
        #expect(supply.value(forKey: "sourceRaw") as? String == "office")
        #expect(supply.value(forKey: "levelChangedAt") == nil, "the launch step will judge it")
        let order = try #require(try fetch("OrderItem", id: orderID, in: context))
        #expect(order.value(forKey: "sourceRaw") as? String == "order", "every order from before is an order")
        #expect(order.value(forKey: "addedByName") as? String == "")
        let transaction = try #require(try fetch("SupplyTransaction", id: transactionID, in: context))
        #expect((transaction.value(forKey: "supply") as? NSManagedObject)?.objectID == supply.objectID)

        // 4. The migrated shared store takes all three, a staple's history beside it.
        let shared = NSEntityDescription.insertNewObject(forEntityName: "Supply", into: context)
        shared.setValue(UUID(), forKey: "id")
        shared.setValue("Tissues", forKey: "name")
        let history = NSEntityDescription.insertNewObject(forEntityName: "SupplyTransaction", into: context)
        history.setValue(UUID(), forKey: "id")
        history.setValue(shared, forKey: "supply")
        let need = NSEntityDescription.insertNewObject(forEntityName: "OrderItem", into: context)
        need.setValue(UUID(), forKey: "id")
        need.setValue("office", forKey: "sourceRaw")
        for row in [shared, history, need] { context.assign(row, to: sharedStore) }
        try context.save()
        #expect([shared, history, need].allSatisfy { $0.objectID.persistentStore == sharedStore })
    }
}
