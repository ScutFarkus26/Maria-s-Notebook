import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

// MARK: - Lightweight Migration Guard
//
// These exist because of a real failure seen in Console: a run of the app on
// 2026-08-23 logged 121 Core Data errors of the form
//
//     no such table: ZGUARDIAN
//     no such table: ZALBUMBOOKMARK
//     table ZLESSON has no column named ZALBUMID
//     no such column: t0.ZDATELASTPROMOTED
//
// — including `NSSQLSaveChangesRequestContext` failures, so writes were being
// dropped, not just reads. Those are the symptoms of a store whose schema is
// behind the model: the entity is in the model, so a fetch or save compiles into
// SQL naming a table or column the store file never got.
//
// The model is a SINGLE .xcdatamodel edited in place — there are no versioned
// model files to migrate between — so a store written by yesterday's build
// depends entirely on `NSMigratePersistentStoresAutomaticallyOption` +
// `NSInferMappingModelAutomaticallyOption` (set in `CoreDataStack.makeStoreDescription`)
// inferring the change. Nothing verified that inference actually worked.
//
// `BackupCoverageTests.everyModelEntityIsRoutedOrKnownDormant` covers the routing
// half of this (an entity assigned to no configuration gets no table anywhere).
// These cover the other half: an entity or attribute that IS routed, but whose
// store predates it.
//
// Two deliberate constraints on how these are written:
//
//  * Objects are created with `NSEntityDescription.insertNewObject(forEntityName:)`
//    and read through KVC rather than the `CD…(context:)` initializers. A reduced
//    model and the bundle's full model are both loaded in-process here, so the
//    class-to-entity lookup behind `NSManagedObject.entity()` has two candidates
//    for the same name — the same ambiguity `CDFetchRequest` exists to avoid.
//  * The suite is serialized: `CoreDataStack` publishes whichever model it was
//    built with to the process-wide `CoreDataStack.activeModel`, and one test here
//    deliberately builds a stack from a reduced model.

@Suite("Store migration", .serialized)
@MainActor
struct StoreMigrationTests {

    // MARK: - Fixtures

    /// Entities and attributes added by the Albums, lesson↔album linking, and Parent
    /// Reports work — i.e. the shape a store written before them would be missing.
    /// Only relationship-free entities can be listed: this app keys records by string
    /// foreign keys rather than Core Data relationships (see CLAUDE.md), so removing
    /// one cannot leave a dangling destination. `removedEntitiesHaveNoRelationships`
    /// enforces that rather than trusting this comment.
    private static let entitiesAddedLater: Set<String> = [
        "Guardian", "AlbumBookmark", "AlbumHighlight"
    ]
    private static let attributesAddedLater: [String: Set<String>] = [
        "Lesson": ["albumID", "albumPageIndex"],
        "Student": ["dateLastPromoted"]
    ]

    // MARK: - Helpers

    private func currentModel() throws -> NSManagedObjectModel {
        let url = try #require(
            Bundle.main.url(forResource: "MariasNotebook", withExtension: "momd"),
            "Compiled model not found in the test host bundle"
        )
        return try #require(NSManagedObjectModel(contentsOf: url), "Compiled model failed to load")
    }

    /// The current model with the later additions stripped out, standing in for the
    /// model as it looked before those features landed.
    private func modelPredatingLaterAdditions() throws -> NSManagedObjectModel {
        let reduced = try #require(try currentModel().copy() as? NSManagedObjectModel)
        reduced.entities = reduced.entities.filter { !Self.entitiesAddedLater.contains($0.name ?? "") }
        for entity in reduced.entities {
            guard let doomed = Self.attributesAddedLater[entity.name ?? ""] else { continue }
            entity.properties = entity.properties.filter { !doomed.contains($0.name) }
        }
        return reduced
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func count(_ entityName: String, in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entityName))
    }

    private func fetchOne(
        _ entityName: String,
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    // MARK: - Tests

    /// Keeps the fixture honest: if one of the entities above gains a relationship,
    /// removing it would produce an invalid model and the migration test below would
    /// fail for a reason that has nothing to do with migration.
    @Test("the entities this suite removes are still relationship-free")
    func removedEntitiesHaveNoRelationships() throws {
        let model = try currentModel()
        for name in Self.entitiesAddedLater.sorted() {
            let entity = try #require(model.entitiesByName[name], "\(name) is no longer in the model")
            #expect(
                entity.relationshipsByName.isEmpty,
                "\(name) gained relationships — it can no longer be removed to build the older model"
            )
            let inbound = model.entities
                .flatMap { $0.relationshipsByName.values }
                .filter { $0.destinationEntity?.name == name }
            #expect(inbound.isEmpty, "\(name) is now the destination of a relationship")
        }
        for (entityName, attributes) in Self.attributesAddedLater {
            let entity = try #require(model.entitiesByName[entityName], "\(entityName) is not in the model")
            let missing = attributes.subtracting(Set(entity.attributesByName.keys))
            #expect(missing.isEmpty, "\(entityName) no longer has \(missing.sorted()) — update the fixture")
        }
    }

    /// The end-to-end shipping scenario: a store written by a build that predates
    /// Albums, Guardians, and the lesson↔album link, reopened by the current model.
    /// Migration must add the new tables and columns and keep what was already there.
    @Test("a store predating Albums and Guardians migrates forward without data loss")
    func storeFromEarlierModelMigratesForward() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("unified.sqlite")

        let lessonID = UUID()
        let studentID = UUID()

        // 1. Write a store using the older shape.
        try autoreleasepool {
            let oldStack = try CoreDataStack(
                enableCloudKit: false,
                localStoreURL: storeURL,
                managedObjectModel: try modelPredatingLaterAdditions()
            )
            let context = oldStack.viewContext

            let lesson = NSEntityDescription.insertNewObject(forEntityName: "Lesson", into: context)
            lesson.setValue(lessonID, forKey: "id")
            lesson.setValue("The Decimal System", forKey: "name")

            let student = NSEntityDescription.insertNewObject(forEntityName: "Student", into: context)
            student.setValue(studentID, forKey: "id")
            student.setValue("Testy", forKey: "firstName")

            try context.save()
        }

        // 2. Reopen the same file with the full current model. A migration failure
        //    surfaces here as a thrown store-load error.
        let migratedStack = try CoreDataStack(enableCloudKit: false, localStoreURL: storeURL)
        let context = migratedStack.viewContext

        // 3. Pre-existing rows survived.
        let lesson = try #require(try fetchOne("Lesson", id: lessonID, in: context), "Lesson lost in migration")
        #expect(lesson.value(forKey: "name") as? String == "The Decimal System")
        let student = try #require(try fetchOne("Student", id: studentID, in: context), "Student lost in migration")
        #expect(student.value(forKey: "firstName") as? String == "Testy")

        // 4. Columns the newer model adds are writable. This is where
        //    `table ZLESSON has no column named ZALBUMID` fired — on save, not on load.
        lesson.setValue("Biology Album.pdf", forKey: "albumID")
        lesson.setValue(Int32(42), forKey: "albumPageIndex")
        student.setValue(Date(timeIntervalSinceReferenceDate: 0), forKey: "dateLastPromoted")
        try context.save()

        context.refreshAllObjects()
        let reread = try #require(try fetchOne("Lesson", id: lessonID, in: context))
        #expect(reread.value(forKey: "albumID") as? String == "Biology Album.pdf")
        #expect(reread.value(forKey: "albumPageIndex") as? Int32 == 42)

        // 5. Tables the newer model adds accept inserts — the `no such table:
        //    ZGUARDIAN` / `ZALBUMBOOKMARK` case.
        let guardianRecord = NSEntityDescription.insertNewObject(forEntityName: "Guardian", into: context)
        guardianRecord.setValue(UUID(), forKey: "id")
        guardianRecord.setValue(studentID.uuidString, forKey: "studentID")
        guardianRecord.setValue("A Parent", forKey: "name")
        guardianRecord.setValue("parent@example.com", forKey: "email")

        let bookmark = NSEntityDescription.insertNewObject(forEntityName: "AlbumBookmark", into: context)
        bookmark.setValue(UUID(), forKey: "id")
        bookmark.setValue("Biology Album.pdf", forKey: "albumID")
        bookmark.setValue(Int32(42), forKey: "pageIndex")

        try context.save()

        #expect(try count("Guardian", in: context) == 1)
        #expect(try count("AlbumBookmark", in: context) == 1)
    }

    /// The broader version of the same guarantee, and the cheaper tripwire: in a
    /// freshly created on-disk store, every routed entity must actually have a table
    /// behind it. An entity in the model but missing from both routing sets reaches
    /// SQLite as `no such table: Z<NAME>` the first time anything touches it — at
    /// runtime, never at store load.
    @Test("every routed entity has a real table in a fresh on-disk store")
    func everyRoutedEntityIsQueryableOnDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stack = try CoreDataStack(
            enableCloudKit: false,
            localStoreURL: directory.appendingPathComponent("unified.sqlite")
        )
        let context = stack.viewContext
        let routed = CoreDataStack.sharedEntityNames.union(CoreDataStack.privateEntityNames)

        var unqueryable: [String] = []
        for name in routed.sorted() {
            do {
                _ = try count(name, in: context)
            } catch {
                unqueryable.append("\(name): \(error.localizedDescription)")
            }
        }

        #expect(
            unqueryable.isEmpty,
            "Routed entities with no usable table on disk:\n\(unqueryable.joined(separator: "\n"))"
        )
    }
}
