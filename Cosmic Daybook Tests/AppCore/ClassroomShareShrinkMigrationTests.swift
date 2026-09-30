import Foundation
import CoreData
import SQLite3
import Testing
@testable import CosmicDaybook

// MARK: - Schema 9 migration: the classroom share shrinks to five types
//
// Schema 9 took 28 entity types out of the Shared configuration and removed the
// Student ↔ StudentTrackEnrollment relationship. Every existing store on a
// Development device was written with the old shape: a lead guide's
// `private.sqlite` holds enrollments linked to students by that relationship,
// and an assistant's `shared.sqlite` holds lessons, tracks and the rest next to
// the students. These open each with the new model the way `CoreDataStack`
// does — `prepareStoresForLoad`, then lightweight migration — and check that
// nothing the new shape still has is lost.
//
// Objects are made with `insertNewObject(forEntityName:)` and read through KVC:
// the schema-8 stand-in and the bundle's model are both loaded here, so the
// class-to-entity lookup behind the `CD…(context:)` initializers is ambiguous.

@Suite("Classroom share shrink migration", .serialized)
@MainActor
struct ClassroomShareShrinkMigrationTests {

    /// `CoreDataStack.sharedEntityNames` as schema 8 had it.
    private static let schema8SharedNames: Set<String> = [
        "Student", "Lesson", "LessonAttachment", "LessonPresentation", "Track", "TrackStep",
        "SequenceTrack", "StudentTrackEnrollment", "Procedure", "Supply", "SupplyTransaction",
        "Schedule", "ScheduleSlot", "CommunityTopic", "ProposedSolution", "CommunityAttachment",
        "ClassroomJob", "JobAssignment", "NoteTemplate", "MeetingTemplate", "TodoTemplate",
        "Resource", "NonSchoolDay", "SchoolDayOverride", "GoingOut", "GoingOutChecklistItem",
        "CalendarNote", "SampleWork", "SampleWorkStep", "ClassroomMembership", "Story",
        "BookClubPacket", "AttendanceRecord"
    ]

    // MARK: - Fixtures

    private func bundleModel() throws -> NSManagedObjectModel {
        let url = try #require(Bundle.main.url(forResource: CoreDataStack.modelName, withExtension: "momd"))
        let loaded = try #require(NSManagedObjectModel(contentsOf: url))
        return try #require(loaded.copy() as? NSManagedObjectModel)
    }

    /// The model as schema 8 had it: no AttendanceDayLock (nor schema 12's
    /// front-desk email types), the enrollment relationship in place, and the
    /// old 33-type Shared configuration.
    private func schema8Model() throws -> NSManagedObjectModel {
        let model = try bundleModel()
        let later: Set<String> = ["AttendanceDayLock", "AttendanceEmailSend", "AttendanceEmailSettings"]
        model.entities = model.entities.filter { !later.contains($0.name ?? "") }
        let byName = model.entitiesByName
        let student = try #require(byName["Student"])
        let enrollment = try #require(byName["StudentTrackEnrollment"])

        let toMany = NSRelationshipDescription()
        toMany.name = "trackEnrollments"
        toMany.destinationEntity = enrollment
        toMany.minCount = 0
        toMany.maxCount = 0
        toMany.isOptional = true
        toMany.deleteRule = .cascadeDeleteRule
        let toOne = NSRelationshipDescription()
        toOne.name = "student"
        toOne.destinationEntity = student
        toOne.minCount = 0
        toOne.maxCount = 1
        toOne.isOptional = true
        toOne.deleteRule = .nullifyDeleteRule
        toMany.inverseRelationship = toOne
        toOne.inverseRelationship = toMany
        student.properties += [toMany]
        enrollment.properties += [toOne]

        let routed = CoreDataStack.privateEntityNames.union(CoreDataStack.sharedEntityNames)
        let shared = model.entities.filter { Self.schema8SharedNames.contains($0.name ?? "") }
        let privateSet = model.entities.filter { routed.contains($0.name ?? "") }
        model.setEntities(shared, forConfigurationName: CoreDataStack.sharedConfiguration)
        model.setEntities(privateSet, forConfigurationName: CoreDataStack.privateConfiguration)
        return model
    }

    private struct TwoStores {
        let directory: URL
        var privateURL: URL { directory.appendingPathComponent("private.sqlite") }
        var sharedURL: URL { directory.appendingPathComponent("shared.sqlite") }
    }

    private func makeDirectory() throws -> TwoStores {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-shrink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return TwoStores(directory: directory)
    }

    private func container(
        _ model: NSManagedObjectModel, stores: TwoStores
    ) -> NSPersistentContainer {
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

    private func fetch(
        _ entityName: String, id: UUID, in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private func seedSchema8Stores(
        _ stores: TwoStores, guideStudent: UUID, enrollmentID: UUID, shared: [(String, UUID)]
    ) throws {
        try autoreleasepool {
            let old = container(try schema8Model(), stores: stores)
            try load(old)
            let context = old.viewContext
            let privateStore = try store(CoreDataStack.privateConfiguration, of: old)
            let sharedStore = try store(CoreDataStack.sharedConfiguration, of: old)

            let student = NSEntityDescription.insertNewObject(forEntityName: "Student", into: context)
            student.setValue(guideStudent, forKey: "id")
            student.setValue("Ada", forKey: "firstName")
            context.assign(student, to: privateStore)
            let enrollment = NSEntityDescription.insertNewObject(forEntityName: "StudentTrackEnrollment", into: context)
            enrollment.setValue(enrollmentID, forKey: "id")
            enrollment.setValue(guideStudent.uuidString, forKey: "studentID")
            enrollment.setValue("track-1", forKey: "trackID")
            enrollment.setValue(student, forKey: "student")
            context.assign(enrollment, to: privateStore)

            for (entity, id) in shared {
                let row = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
                row.setValue(id, forKey: "id")
                context.assign(row, to: sharedStore)
            }
            try context.save()
            for store in old.persistentStoreCoordinator.persistentStores {
                try old.persistentStoreCoordinator.remove(store)
            }
        }
    }

    // MARK: - Tests

    @Test("Schema-8 stores open with schema 9 and keep what the new shape holds")
    func schema8StoresMigrate() throws {
        let stores = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: stores.directory) }
        let guideStudent = UUID(), enrollmentID = UUID(), sharedStudent = UUID(), sharedLesson = UUID()
        let attendanceID = UUID(), holidayID = UUID()

        // 1. Schema 8: the guide's enrollment linked by relationship in the
        //    private store; an assistant-style shared store holding a student,
        //    attendance, a holiday and a lesson.
        try seedSchema8Stores(stores, guideStudent: guideStudent, enrollmentID: enrollmentID, shared: [
            ("Student", sharedStudent), ("Lesson", sharedLesson),
            ("AttendanceRecord", attendanceID), ("NonSchoolDay", holidayID)
        ])

        // 2. Schema 9, prepared exactly as `CoreDataStack.init` prepares it.
        let model = try CoreDataStack.sharedModel()
        let new = container(model, stores: stores)
        try CoreDataStack.prepareStoresForLoad(container: new, model: model)
        try load(new)
        let context = new.viewContext

        // 3. The guide's enrollment survives the relationship's removal.
        let enrollment = try #require(try fetch("StudentTrackEnrollment", id: enrollmentID, in: context))
        #expect(enrollment.value(forKey: "studentID") as? String == guideStudent.uuidString)
        #expect(try fetch("Student", id: guideStudent, in: context) != nil)

        // 4. The shared store keeps its five types; the lesson it can no
        //    longer hold is gone from it (an assistant never needed it).
        let sharedStore = try store(CoreDataStack.sharedConfiguration, of: new)
        for (entity, id) in [("Student", sharedStudent), ("AttendanceRecord", attendanceID),
                             ("NonSchoolDay", holidayID)] {
            let row = try #require(try fetch(entity, id: id, in: context), "\(entity) lost in migration")
            #expect(row.objectID.persistentStore == sharedStore)
        }
        #expect(try fetch("Lesson", id: sharedLesson, in: context) == nil)

        // 5. The new shared type is writable in the migrated shared store.
        let lock = NSEntityDescription.insertNewObject(forEntityName: "AttendanceDayLock", into: context)
        lock.setValue(UUID(), forKey: "id")
        lock.setValue(Date(), forKey: "date")
        context.assign(lock, to: sharedStore)
        try context.save()
    }

    @Test("Mirroring metadata for types that left a store's configuration is cleared")
    func metadataCleanupFollowsConfiguration() throws {
        let stores = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: stores.directory) }

        try autoreleasepool {
            let old = container(try schema8Model(), stores: stores)
            try load(old)
            let context = old.viewContext
            let sharedStore = try store(CoreDataStack.sharedConfiguration, of: old)
            for entity in ["Student", "Lesson"] {
                let row = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
                row.setValue(UUID(), forKey: "id")
                context.assign(row, to: sharedStore)
            }
            try context.save()
            for store in old.persistentStoreCoordinator.persistentStores {
                try old.persistentStoreCoordinator.remove(store)
            }
        }

        // A stand-in for the CloudKit mirror's record metadata: one row per
        // record, keyed by the entity's Z_ENT.
        let entityIDs = try Self.withDatabase(stores.sharedURL) { db in
            Self.execute(
                db, "CREATE TABLE ANSCKRECORDMETADATA (Z_PK INTEGER PRIMARY KEY, ZENTITYID INTEGER, ZENTITYPK INTEGER)"
            )
            var ids: [String: Int64] = [:]
            for name in ["Student", "Lesson"] {
                let zEnt = try #require(Self.queryInt(db, "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = '\(name)'"))
                ids[name] = zEnt
                Self.execute(db, "INSERT INTO ANSCKRECORDMETADATA (ZENTITYID, ZENTITYPK) VALUES (\(zEnt), 1)")
            }
            return ids
        }
        let model = try CoreDataStack.sharedModel()

        // Judged against the whole model, Lesson is still an entity: nothing goes.
        CoreDataStack.cleanOrphanEntityMetadata(storeURL: stores.sharedURL, model: model)
        #expect(try metadataCount(stores.sharedURL, entityID: entityIDs["Lesson"]) == 1)

        // Judged against the Shared configuration, Lesson has left the store.
        CoreDataStack.cleanOrphanEntityMetadata(
            storeURL: stores.sharedURL, model: model, configuration: CoreDataStack.sharedConfiguration
        )
        #expect(try metadataCount(stores.sharedURL, entityID: entityIDs["Lesson"]) == 0)
        #expect(try metadataCount(stores.sharedURL, entityID: entityIDs["Student"]) == 1)
    }

    // MARK: - SQLite helpers

    private func metadataCount(_ url: URL, entityID: Int64?) throws -> Int64 {
        let id = try #require(entityID)
        return try Self.withDatabase(url) { db in
            try #require(Self.queryInt(db, "SELECT COUNT(*) FROM ANSCKRECORDMETADATA WHERE ZENTITYID = \(id)"))
        }
    }

    private static func withDatabase<T>(_ url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(handle) }
        return try body(handle)
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private static func queryInt(_ db: OpaquePointer, _ sql: String) -> Int64? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }
}
