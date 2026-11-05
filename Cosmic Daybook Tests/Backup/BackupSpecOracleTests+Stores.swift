import CoreData
import CryptoKit
import Foundation
import Testing
@testable import CosmicDaybook

// `BackupSpecOracleTests`' stores and the text it compares: the fixture
// stores a restore goes into, a type's records as comparable fields, the
// golden backup's rows, and the app's reading and Merge of one line.

/// For the test bundle's golden backup.
private final class GoldenToken {}

extension BackupSpecOracleTests {

    // MARK: - Stores

    /// A store holding the field-coverage fixture, saved, less the record of
    /// `type` with id `without` when one is given.
    static func fixtureStore(without id: UUID?, of type: NSManagedObject.Type) throws -> CoreDataStack {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: context)
        if let id {
            let name = try #require(entityName(of: type, in: context))
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let records = try context.fetch(request)
            #expect(!records.isEmpty, "The fixture holds no \(name) \(id)")
            records.forEach(context.delete)
        }
        #expect(CoreDataTestHelpers.save(context), "Fixture save failed")
        return stack
    }

    /// Two stores holding the fixture (less one record of a type, for an
    /// insert), one for the old restore and one for the app's, kept for every
    /// case of a row: seeding a store costs far more than restoring a row, and
    /// more the longer the test host has run. `putBack()` returns each to what
    /// it was built with, checks that it did, and builds it again when not.
    final class FixturePair {
        private let type: NSManagedObject.Type
        private let without: UUID?
        private var oldSide: Side
        private var newSide: Side

        var old: NSManagedObjectContext { oldSide.stack.viewContext }
        var new: NSManagedObjectContext { newSide.stack.viewContext }

        init(of type: NSManagedObject.Type, without id: UUID?) throws {
            self.type = type
            without = id
            oldSide = try Side(BackupSpecOracleTests.fixtureStore(without: id, of: type))
            newSide = try Side(BackupSpecOracleTests.fixtureStore(without: id, of: type))
        }

        func putBack() throws {
            if !oldSide.putBack() {
                oldSide = try Side(BackupSpecOracleTests.fixtureStore(without: without, of: type))
            }
            if !newSide.putBack() {
                newSide = try Side(BackupSpecOracleTests.fixtureStore(without: without, of: type))
            }
        }
    }

    /// One store, every record in it as built, and those records as text.
    private struct Side {
        let stack: CoreDataStack
        let built: [NSManagedObjectID: Built]
        let text: [String]

        init(_ stack: CoreDataStack) throws {
            self.stack = stack
            let context = stack.viewContext
            built = try BackupSpecOracleTests.everything(in: context)
                .reduce(into: [:]) { $0[$1.objectID] = Built($1) }
            context.refreshAllObjects()
            text = try BackupSpecOracleTests.storeText(of: context)
        }

        /// Deletes what a restore made, sets back what it changed, and says
        /// whether the saved store now reads as it did when built.
        func putBack() -> Bool {
            let context = stack.viewContext
            context.rollback()
            do {
                for object in try BackupSpecOracleTests.everything(in: context) where built[object.objectID] == nil {
                    context.delete(object)
                }
                context.processPendingChanges()
                for (objectID, record) in built {
                    let object = try context.existingObject(with: objectID)
                    guard !object.isDeleted else { return false }
                    try record.setBack(on: object)
                }
                if context.hasChanges { try context.save() }
                context.refreshAllObjects()
                return try BackupSpecOracleTests.storeText(of: context) == text
            } catch {
                context.rollback()
                return false
            }
        }
    }

    /// A record's attributes (NSNull for nil) and relationship targets.
    private struct Built {
        let attributes: [String: Any]
        let targets: [String: [NSManagedObjectID]]

        init(_ object: NSManagedObject) {
            attributes = object.entity.attributesByName.keys
                .reduce(into: [:]) { $0[$1] = object.value(forKey: $1) ?? NSNull() }
            targets = object.entity.relationshipsByName.keys
                .reduce(into: [:]) { $0[$1] = BackupSpecOracleTests.targets(of: object, $1) }
        }

        func setBack(on object: NSManagedObject) throws {
            guard let context = object.managedObjectContext else { return }
            for (key, value) in attributes
            where !((object.value(forKey: key) ?? NSNull()) as AnyObject).isEqual(value) {
                object.setValue(value is NSNull ? nil : value, forKey: key)
            }
            for (key, relationship) in object.entity.relationshipsByName {
                let was = targets[key] ?? []
                let now = BackupSpecOracleTests.targets(of: object, key)
                guard relationship.isOrdered ? was != now : Set(was) != Set(now) else { continue }
                let objects = try was.map { try context.existingObject(with: $0) }
                if !relationship.isToMany {
                    object.setValue(objects.first, forKey: key)
                } else if relationship.isOrdered {
                    object.setValue(NSOrderedSet(array: objects), forKey: key)
                } else {
                    object.setValue(NSSet(array: objects), forKey: key)
                }
            }
        }
    }

    /// Every record in the store, of every entity.
    static func everything(in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let entities = context.persistentStoreCoordinator?.managedObjectModel.entities ?? []
        return try entities.filter { !$0.isAbstract }.flatMap { entity -> [NSManagedObject] in
            guard let name = entity.name else { return [] }
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.includesSubentities = false
            return try context.fetch(request)
        }
    }

    /// The whole store as sorted lines, one per record: its entity, object
    /// ID, attributes and relationship targets.
    static func storeText(of context: NSManagedObjectContext) throws -> [String] {
        let recent = Date().addingTimeInterval(-3_600)
        return try everything(in: context).map { object in
            let entity = object.entity
            var fields = entity.attributesByName.keys.map { "\($0)=\(text(object.value(forKey: $0), recent: recent))" }
            for (key, relationship) in entity.relationshipsByName {
                let uris = targets(of: object, key).map { $0.uriRepresentation().absoluteString }
                fields.append("→\(key)=" + (relationship.isOrdered ? uris : uris.sorted()).joined(separator: ","))
            }
            let name = "\(entity.name ?? "?") \(object.objectID.uriRepresentation().absoluteString)"
            return ([name] + fields.sorted()).joined(separator: "\t")
        }.sorted()
    }

    static func targets(of object: NSManagedObject, _ key: String) -> [NSManagedObjectID] {
        switch object.value(forKey: key) {
        case let one as NSManagedObject: [one.objectID]
        case let set as NSSet: set.allObjects.compactMap { ($0 as? NSManagedObject)?.objectID }
        case let ordered as NSOrderedSet: ordered.array.compactMap { ($0 as? NSManagedObject)?.objectID }
        default: []
        }
    }

    /// Every record of `type` by id: each attribute, and each to-one
    /// relationship as its target's id ("→name"). A date from the last hour,
    /// stamped by the restore rather than carried by the row, reads "recent".
    static func records(
        of type: NSManagedObject.Type,
        in context: NSManagedObjectContext
    ) throws -> [String: [String: String]] {
        guard let name = entityName(of: type, in: context) else { return [:] }
        let request = NSFetchRequest<NSManagedObject>(entityName: name)
        request.includesSubentities = false
        let recent = Date().addingTimeInterval(-3_600)
        var result: [String: [String: String]] = [:]
        for (offset, object) in try context.fetch(request).enumerated() {
            var fields: [String: String] = [:]
            for key in object.entity.attributesByName.keys {
                fields[key] = text(object.value(forKey: key), recent: recent)
            }
            for (key, relationship) in object.entity.relationshipsByName where !relationship.isToMany {
                let target = object.value(forKey: key) as? NSManagedObject
                fields["→\(key)"] = target.map { ($0.value(forKey: "id") as? UUID)?.uuidString ?? "<no id>" } ?? "nil"
            }
            let id = (object.value(forKey: "id") as? UUID)?.uuidString ?? "<no id \(offset)>"
            result[id] = fields
        }
        return result
    }

    static func text(_ value: Any?, recent: Date) -> String {
        guard let value, !(value is NSNull) else { return "nil" }
        switch value {
        case let date as Date:
            return date > recent ? "recent" : "\(date.timeIntervalSinceReferenceDate)"
        case let uuid as UUID:
            return uuid.uuidString
        case let data as Data:
            // A JSON blob (a note's scope) by content: it is encoded without sorted keys.
            if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
               let sorted = try? JSONSerialization.data(
                   withJSONObject: json, options: [.sortedKeys, .fragmentsAllowed]
               ) {
                return "json(\(String(bytes: sorted, encoding: .utf8) ?? ""))"
            }
            let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
            return "data(\(data.count),\(digest))"
        default:
            return "\(value)"
        }
    }

    // MARK: - Helpers

    /// The golden backup (`BackupGoldenOutputTests`): `<store>/<Entity>` → NDJSON body.
    static let golden: [String: String] = {
        guard let url = Bundle(for: GoldenToken.self).url(forResource: "BackupGolden-v27", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }()

    /// The app's reading of one line of `entityName`: the payload holding its
    /// row, or nil when the reader refused it.
    static func appRead(_ line: Data, entityName: String, storeName: String) -> BackupPayload? {
        let entry = BackupEntityEntry(
            entityName: entityName, storeName: storeName, count: 1, ndjson: line + Data([0x0A])
        )
        let manifest = BackupArchiveManifest(
            formatVersion: BackupWriter.formatVersion, createdAt: Date(),
            appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
        )
        let (payload, _) = BackupImporter.reconstructPayload(
            from: BackupReader.DecodedBackup(manifest: manifest, entries: [entry], preferences: nil)
        )
        let rows = BackupEntityTable.entities.first { $0.name == entityName }?.rowsIn(payload)?.count ?? 0
        return rows == 1 ? payload : nil
    }

    /// The app's Merge of `payload` into `context`: nil, or why it failed.
    static func appMerge(_ payload: BackupPayload, into context: NSManagedObjectContext) async -> String? {
        do {
            _ = try await BackupService().importPayload(
                payload: payload,
                envelope: BackupEnvelope(
                    formatVersion: BackupWriter.formatVersion, encrypted: false, createdAt: Date(),
                    fileName: "spec-oracle", entityCounts: [:]
                ),
                viewContext: context,
                mode: .merge,
                appRouter: AppRouter.shared,
                progress: { _, _ in }
            )
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// `type`'s entity name in this context's model (the class method can be
    /// ambiguous with the test host's model loaded too).
    static func entityName(of type: NSManagedObject.Type, in context: NSManagedObjectContext) -> String? {
        context.persistentStoreCoordinator?.managedObjectModel.entitiesByName.values
            .first { $0.managedObjectClassName == NSStringFromClass(type) }?.name
    }

    static func object(_ line: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }

    /// A row value as comparable text; a string holding a JSON object (a
    /// note's scope, written from a dictionary with no fixed key order) by its
    /// content.
    static func canonical(_ value: Any?) -> String {
        guard var value else { return "(not written)" }
        if let text = value as? String, text.hasPrefix("{"),
           let nested = try? JSONSerialization.jsonObject(with: Data(text.utf8)) {
            value = nested
        }
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: options) else {
            return "\(value)"
        }
        return String(bytes: data, encoding: .utf8) ?? "\(value)"
    }

    static func fixedUUID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", 0x5EC0 + index)) ?? UUID()
    }
}
