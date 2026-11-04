import Foundation
import CoreData
import SQLite3
import Testing
@testable import CosmicDaybook

// MARK: - Schema 23: the track entities leave the model
//
// A store written at schema 22 (the bundle's model plus `TrackEntitiesStandIn`)
// opens with the current model the way `CoreDataStack` opens it —
// `prepareStoresForLoad`, then lightweight migration. The migration drops the
// four tables and the columns that named them, and before it runs the
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
    /// stamped with a track.
    private struct Seeded {
        let onEnrollment = UUID()
        let namesClassmate = UUID()
        let onGoneEnrollment = UUID()
        let wholeClass = UUID()
        let presentation = UUID()
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

    private func seedSchema22Stores(_ stores: TwoStores) throws -> Seeded {
        let seeded = Seeded()
        try autoreleasepool {
            let old = container(try schema22Model(), stores: stores)
            try load(old)
            let context = old.viewContext
            let privateStore = try #require(old.persistentStoreCoordinator.persistentStores.first {
                $0.configurationName == CoreDataStack.privateConfiguration
            })
            let enrollment = UUID()
            insert("Student", ["id": child, "firstName": "Ada"], into: context, store: privateStore)
            insert("Track", ["id": UUID(), "title": "Math — Fractions"], into: context, store: privateStore)
            insert("StudentTrackEnrollment", [
                "id": enrollment, "studentID": child.uuidString, "trackID": "track-1"
            ], into: context, store: privateStore)
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
                insert("Note", values, into: context, store: privateStore)
            }
            insert("LessonPresentation", [
                "id": seeded.presentation, "studentID": child.uuidString, "lessonID": UUID().uuidString,
                "trackID": "track-1", "trackStepID": "step-1"
            ], into: context, store: privateStore)
            try context.save()
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

        // 2. The tables and the columns are gone; the rows that carried a
        //    column are not.
        #expect(Self.columns(of: "ZSTUDENTTRACKENROLLMENT", at: stores.privateURL).isEmpty)
        #expect(Self.columns(of: "ZTRACK", at: stores.privateURL).isEmpty)
        #expect(!Self.columns(of: "ZNOTE", at: stores.privateURL).contains("ZSTUDENTTRACKENROLLMENTID"))
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
