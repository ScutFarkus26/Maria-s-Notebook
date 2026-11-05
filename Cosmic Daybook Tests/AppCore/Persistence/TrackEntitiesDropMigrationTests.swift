import Foundation
import CoreData
import SQLite3
import Testing
@testable import CosmicDaybook

// MARK: - Schema 23: the track entities leave the private store
//
// A store written at schema 22 (the bundle's model with the four track
// entities routed to Private, plus `TrackEntitiesStandIn`'s columns) opens with
// the current model the way `CoreDataStack` opens it — `prepareStoresForLoad`,
// then lightweight migration. The four stay in the model as dormant tombstones
// in no store, so the migration drops the columns that named them, leaves
// their tables in the file where no store reads them (as the other tombstones'
// are), and keeps the store's persistent history: deleting them from the model
// would have expired every history token older than the last save, which
// forces the CloudKit mirror into a full reset. Before the migration runs, the
// preparation reads, straight from the file, whose each note on an enrollment
// is (`EnrollmentNoteOwners`); the launch pass then moves those notes onto
// that child (`docs/Plans/Plan - Retire the track entities.md`, Phase 3).
//
// Objects are made with `insertNewObject(forEntityName:)` and read through KVC
// on the old side: both models are loaded here, so the class-to-entity lookup
// behind the `CD…(context:)` initializers is ambiguous.

@Suite("Track entities drop migration (schema 23)", .serialized)
@MainActor
struct TrackEntitiesDropMigrationTests {

    private let child = UUID()
    private let classmate = UUID()

    // MARK: - Fixtures

    private struct TwoStores {
        let directory: URL
        var privateURL: URL { directory.appendingPathComponent("private.sqlite") }
        var sharedURL: URL { directory.appendingPathComponent("shared.sqlite") }
    }

    /// What the schema-22 store held: a note on an enrollment that names no
    /// child, one on the same enrollment that names a classmate, one on an
    /// enrollment that is gone, a whole-class note on none, and a presentation
    /// stamped with a track; saved three times, with the private store's
    /// history token after each save, archived.
    private struct Seeded {
        let onEnrollment = UUID()
        let namesClassmate = UUID()
        let onGoneEnrollment = UUID()
        let wholeClass = UUID()
        let presentation = UUID()
        var historyTokens: [Data] = []
    }

    /// What the private store's history holds after a token.
    private struct HistoryRead {
        let transactions: Int
        let entities: Set<String>
    }

    /// A schema-22 note: its id, the enrollment it named, and its own scope.
    private struct OldNote {
        let id: UUID
        let enrollmentID: String?
        let scope: NoteScope
    }

    /// The model as schema 22 had it, with the app's two configurations.
    private func schema22Model() throws -> NSManagedObjectModel {
        let url = try #require(Bundle.main.url(forResource: CoreDataStack.modelName, withExtension: "momd"))
        let loaded = try #require(NSManagedObjectModel(contentsOf: url))
        let model = try #require(loaded.copy() as? NSManagedObjectModel)
        TrackEntitiesStandIn.add(to: model)
        let shared = model.entities.filter { CoreDataStack.sharedEntityNames.contains($0.name ?? "") }
        let privateNames = CoreDataStack.privateEntityNames.union(TrackEntitiesStandIn.names)
        let privateOnly = model.entities.filter { privateNames.contains($0.name ?? "") }
        model.setEntities(shared, forConfigurationName: CoreDataStack.sharedConfiguration)
        model.setEntities(privateOnly + shared, forConfigurationName: CoreDataStack.privateConfiguration)
        return model
    }

    private func makeDirectory() throws -> TwoStores {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("track-drop-\(UUID().uuidString)", isDirectory: true)
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

    private func insert(
        _ entity: String, _ values: [String: Any], into context: NSManagedObjectContext, store: NSPersistentStore
    ) {
        let row = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        for (key, value) in values { row.setValue(value, forKey: key) }
        context.assign(row, to: store)
    }

    private func scopeBlob(_ scope: NoteScope) throws -> Data {
        try JSONEncoder().encode(scope)
    }

    private func insertNotes(
        of seeded: Seeded, enrollment: UUID, into context: NSManagedObjectContext, store: NSPersistentStore
    ) throws {
        let notes: [OldNote] = [
            OldNote(id: seeded.onEnrollment, enrollmentID: enrollment.uuidString, scope: .all),
            OldNote(
                id: seeded.namesClassmate, enrollmentID: enrollment.uuidString.lowercased(),
                scope: .student(classmate)
            ),
            OldNote(id: seeded.onGoneEnrollment, enrollmentID: UUID().uuidString, scope: .all),
            OldNote(id: seeded.wholeClass, enrollmentID: nil, scope: .all)
        ]
        for note in notes {
            var values: [String: Any] = [
                "id": note.id, "body": "Ready for the next fraction", "scopeBlob": try scopeBlob(note.scope),
                "scopeIsAll": note.scope == .all
            ]
            if let enrollmentID = note.enrollmentID { values["studentTrackEnrollmentID"] = enrollmentID }
            insert("Note", values, into: context, store: store)
        }
    }

    private func seedSchema22Stores(_ stores: TwoStores) throws -> Seeded {
        var seeded = Seeded()
        try autoreleasepool {
            let old = container(try schema22Model(), stores: stores)
            try load(old)
            let context = old.viewContext
            let privateStore = try #require(old.persistentStoreCoordinator.persistentStores.first {
                $0.configurationName == CoreDataStack.privateConfiguration
            })
            func checkpoint() throws {
                try context.save()
                let token = try #require(old.persistentStoreCoordinator.currentPersistentHistoryToken(
                    fromStores: [privateStore]
                ))
                seeded.historyTokens.append(
                    try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                )
            }
            let enrollment = UUID()
            insert("Student", ["id": child, "firstName": "Ada"], into: context, store: privateStore)
            insert("Track", ["id": UUID(), "title": "Math — Fractions"], into: context, store: privateStore)
            insert("StudentTrackEnrollment", [
                "id": enrollment, "studentID": child.uuidString, "trackID": "track-1"
            ], into: context, store: privateStore)
            try checkpoint()
            try insertNotes(of: seeded, enrollment: enrollment, into: context, store: privateStore)
            try checkpoint()
            insert("LessonPresentation", [
                "id": seeded.presentation, "studentID": child.uuidString, "lessonID": UUID().uuidString,
                "trackID": "track-1", "trackStepID": "step-1"
            ], into: context, store: privateStore)
            try checkpoint()
            for store in old.persistentStoreCoordinator.persistentStores {
                try old.persistentStoreCoordinator.remove(store)
            }
        }
        return seeded
    }

    // MARK: - Tests

    @Test("A schema-22 store migrates, keeping whose each enrollment note is, and the launch step moves it")
    func schema22StoreMigrates() throws {
        let stores = try makeDirectory()
        let standard = UserDefaults.standard
        let suiteName = "TrackEntitiesDropMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: stores.directory)
            standard.removeObject(forKey: EnrollmentNoteOwners.defaultsKey)
            defaults.removePersistentDomain(forName: suiteName)
        }
        standard.removeObject(forKey: EnrollmentNoteOwners.defaultsKey)
        // `CDFetchRequest` names an entity from the app's model, which a stack
        // records; the stand-in's copies of the classes would make the
        // class's own `entity()` ambiguous.
        let modelHolder = try CoreDataTestHelpers.makeInMemoryStack()
        let seeded = try seedSchema22Stores(stores)

        // 1. Prepared exactly as `CoreDataStack.init` prepares it: the list is
        //    read from the file before it migrates.
        let model = try CoreDataStack.sharedModel()
        let new = container(model, stores: stores)
        try CoreDataStack.prepareStoresForLoad(container: new, model: model)
        let stashed = standard.dictionary(forKey: EnrollmentNoteOwners.defaultsKey) as? [String: String]
        standard.removeObject(forKey: EnrollmentNoteOwners.defaultsKey)
        #expect(stashed == [
            seeded.onEnrollment.uuidString: child.uuidString,
            seeded.namesClassmate.uuidString: child.uuidString
        ])
        defaults.set(stashed, forKey: EnrollmentNoteOwners.defaultsKey)
        try load(new)
        let context = new.viewContext

        // 2. The columns are gone; the rows that carried a column are not.
        //    The enrollments stay in their table, which no store reads now.
        #expect(!Self.columns(of: "ZNOTE", at: stores.privateURL).contains("ZSTUDENTTRACKENROLLMENTID"))
        #expect(!Self.columns(of: "ZNOTE", at: stores.privateURL).isEmpty)
        let privateNames = model.entities(forConfigurationName: CoreDataStack.privateConfiguration)?
            .compactMap(\.name) ?? []
        #expect(!privateNames.contains("StudentTrackEnrollment") && !privateNames.contains("Track"))
        #expect(!Self.columns(of: "ZLESSONPRESENTATION", at: stores.privateURL).contains("ZTRACKID"))
        #expect(!Self.columns(of: "ZLESSONPRESENTATION", at: stores.privateURL).isEmpty)
        let presentations = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        #expect(presentations.map(\.id) == [seeded.presentation])

        // 3. Read again, the migrated file has nothing left to give.
        #expect(EnrollmentNoteOwners.read(storeURL: stores.privateURL).isEmpty)

        // 4. The launch step moves the note that named no child; the one that
        //    named a classmate keeps her, and the rest are untouched.
        #expect(EnrollmentNoteOwners.apply(using: context, defaults: defaults) == 1)
        try context.save()
        let notes = Dictionary(
            uniqueKeysWithValues: context.safeFetch(CDFetchRequest(CDNote.self)).compactMap { note in
                note.id.map { ($0, note.scope) }
            }
        )
        #expect(notes[seeded.onEnrollment] == .student(child))
        #expect(notes[seeded.namesClassmate] == .student(classmate))
        #expect(notes[seeded.onGoneEnrollment] == .all)
        #expect(notes[seeded.wholeClass] == .all)
        EnrollmentNoteOwners.forget(defaults: defaults)
        #expect(!EnrollmentNoteOwners.isPending(defaults: defaults))
        withExtendedLifetime(modelHolder) {}
    }

    @Test("History from before the migration still reads after it: the four left the store, not the model")
    func historySurvivesTheMigration() throws {
        let stores = try makeDirectory()
        let standard = UserDefaults.standard
        defer {
            try? FileManager.default.removeItem(at: stores.directory)
            standard.removeObject(forKey: EnrollmentNoteOwners.defaultsKey)
        }
        let modelHolder = try CoreDataTestHelpers.makeInMemoryStack()
        let seeded = try seedSchema22Stores(stores)
        #expect(seeded.historyTokens.count == 3)

        let model = try CoreDataStack.sharedModel()
        let new = container(model, stores: stores)
        try CoreDataStack.prepareStoresForLoad(container: new, model: model)
        standard.removeObject(forKey: EnrollmentNoteOwners.defaultsKey)
        try load(new)

        // The four are dormant tombstones: in the model, in neither store.
        let privateNames = Set(model.entities(forConfigurationName: CoreDataStack.privateConfiguration)?
            .compactMap(\.name) ?? [])
        let sharedNames = Set(model.entities(forConfigurationName: CoreDataStack.sharedConfiguration)?
            .compactMap(\.name) ?? [])
        #expect(privateNames.contains("Note") && sharedNames.contains("Student"))
        for name in TrackEntitiesStandIn.names {
            #expect(model.entitiesByName[name] != nil, "\(name) left the model")
            #expect(!privateNames.contains(name) && !sharedNames.contains(name), "\(name) is still in a store")
        }

        // Every token from before the migration still resolves, the first
        // save's included (deleting the entities expired all but the last),
        // and the saves after it are still there.
        let privateStore = try #require(new.persistentStoreCoordinator.persistentStores.first {
            $0.configurationName == CoreDataStack.privateConfiguration
        })
        for (index, data) in seeded.historyTokens.enumerated() {
            let token = try #require(try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self, from: data
            ))
            let read = try history(after: token, in: privateStore, context: new.viewContext)
            #expect(read.transactions >= seeded.historyTokens.count - 1 - index, "after save \(index + 1)")
        }
        // The changes to the track entities themselves are still in it.
        let all = try history(after: nil, in: privateStore, context: new.viewContext)
        #expect(all.transactions >= seeded.historyTokens.count)
        #expect(all.entities.isSuperset(of: ["Track", "StudentTrackEnrollment", "Note", "LessonPresentation"]))
        withExtendedLifetime(modelHolder) {}
    }

    @Test("A store already at schema 23 is read for nothing and stashes nothing")
    func currentStoreStashesNothing() throws {
        let stores = try makeDirectory()
        let standard = UserDefaults.standard
        defer {
            try? FileManager.default.removeItem(at: stores.directory)
            standard.removeObject(forKey: EnrollmentNoteOwners.defaultsKey)
        }
        standard.removeObject(forKey: EnrollmentNoteOwners.defaultsKey)
        let model = try CoreDataStack.sharedModel()
        try autoreleasepool {
            let first = container(model, stores: stores)
            try load(first)
            for store in first.persistentStoreCoordinator.persistentStores {
                try first.persistentStoreCoordinator.remove(store)
            }
        }

        let again = container(model, stores: stores)
        try CoreDataStack.prepareStoresForLoad(container: again, model: model)
        #expect(standard.object(forKey: EnrollmentNoteOwners.defaultsKey) == nil)
        #expect(EnrollmentNoteOwners.read(storeURL: stores.privateURL).isEmpty)
    }

}

extension TrackEntitiesDropMigrationTests {

    // MARK: - History

    /// The private store's history after `token`, read on `context` (the
    /// view context, on the main queue like this suite); throws when the
    /// token has expired (`NSPersistentHistoryTokenExpiredError`).
    private func history(
        after token: NSPersistentHistoryToken?, in store: NSPersistentStore, context: NSManagedObjectContext
    ) throws -> HistoryRead {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.resultType = .transactionsAndChanges
        request.affectedStores = [store]
        let result = try context.execute(request) as? NSPersistentHistoryResult
        let transactions = result?.result as? [NSPersistentHistoryTransaction] ?? []
        let entities = transactions.flatMap { $0.changes ?? [] }.compactMap(\.changedObjectID.entity.name)
        return HistoryRead(transactions: transactions.count, entities: Set(entities))
    }

    // MARK: - SQLite

    /// The column names of `table` in the file at `url`; empty when there is no such table.
    private static func columns(of table: String, at url: URL) -> Set<String> {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            return []
        }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) { names.insert(String(cString: name)) }
        }
        return names
    }
}
