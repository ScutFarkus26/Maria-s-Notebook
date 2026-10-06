import CoreData
import Foundation
import SQLite3
@testable import CosmicDaybook

/// A throwaway folder for store-file tests, with a one-entity model (`Thing`)
/// small enough to build stores from in a line, and an optional second
/// attribute so a store made without it needs migrating.
@MainActor
struct StoreFileFixture {
    struct NoThingEntity: Error {}

    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreFileFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// `Thing(title)`, or `Thing(title, note)` with `withNote`.
    static func model(withNote: Bool = false) -> NSManagedObjectModel {
        var properties: [NSPropertyDescription] = []
        for name in withNote ? ["title", "note"] : ["title"] {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = .stringAttributeType
            attribute.isOptional = true
            properties.append(attribute)
        }
        let entity = NSEntityDescription()
        entity.name = "Thing"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = properties
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    /// A store at `url` holding `rows` things, closed again.
    @discardableResult
    static func makeStore(at url: URL, model: NSManagedObjectModel, rows: Int) throws -> URL {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
        try addRows(rows, to: coordinator, model: model)
        try coordinator.remove(store)
        return url
    }

    /// Inserts and saves `rows` things through `coordinator`.
    static func addRows(_ rows: Int, to coordinator: NSPersistentStoreCoordinator, model: NSManagedObjectModel) throws {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        guard let entity = model.entitiesByName["Thing"] else { throw NoThingEntity() }
        for index in 0..<rows {
            NSManagedObject(entity: entity, insertInto: context).setValue("thing \(index)", forKey: "title")
        }
        try context.save()
    }

    /// How many things the file holds, read straight from SQLite (-1: unreadable).
    static func rowCount(at url: URL) -> Int {
        integer(at: url, "SELECT COUNT(*) FROM ZTHING") ?? -1
    }

    /// The `Z_MAX` counter for `Thing`.
    static func thingCounter(at url: URL) -> Int? {
        integer(at: url, "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = 'Thing'")
    }

    static func execute(at url: URL, _ sql: String) -> Bool {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { return false }
        defer { sqlite3_close(handle) }
        return sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK
    }

    /// The schema stamp in the store's on-disk metadata.
    static func stamp(at url: URL) -> Int? {
        let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        return metadata?[CoreDataStack.schemaVersionMetadataKey] as? Int
    }

    /// A container with one SQLite store description at `url`, not loaded.
    static func container(model: NSManagedObjectModel, url: URL) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "StoreFileFixture", managedObjectModel: model)
        container.persistentStoreDescriptions = [CoreDataStack.makeStoreDescription(url: url, configuration: nil)]
        return container
    }

    private static func integer(at url: URL, _ sql: String) -> Int? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
