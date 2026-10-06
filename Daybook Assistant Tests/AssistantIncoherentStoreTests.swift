import CoreData
import Foundation
import SQLite3
import Testing
@testable import Daybook_Assistant

// Hunt of 2026-10-05, #18: an assistant's shared store whose files had lost a
// column was moved aside at launch and rebuilt from iCloud, silently losing the
// marks she hadn't sent yet. The notebook's guide has nothing unsent there to
// lose; she does. Now the startup screen says the class's copy is damaged and
// offers the rebuild, which warns first.

@Suite("Assistant: a damaged shared store")
@MainActor
struct AssistantIncoherentStoreTests {

    @Test("A shared store missing a table stops the start instead of being moved aside")
    func incoherentSharedStoreThrows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("assistant-incoherent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("shared.sqlite")
        let model = try CoreDataStack.sharedModel()

        // A real shared store, then the scar an older build's half-finished
        // migration leaves: a table gone while the metadata still matches.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(
            type: .sqlite, configuration: CoreDataStack.sharedConfiguration, at: url
        )
        try coordinator.remove(store)
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        #expect(sqlite3_exec(handle, "DROP TABLE ZCLASSROOMPERSON", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)

        let container = NSPersistentContainer(name: "AssistantIncoherent", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.configuration = CoreDataStack.sharedConfiguration
        container.persistentStoreDescriptions = [description]

        var thrown: CoreDataStackError?
        do {
            try CoreDataStack.prepareStoresForLoad(container: container, model: model)
        } catch let error as CoreDataStackError {
            thrown = error
        }
        guard let thrown, case .storeSchemaIncoherent = thrown else {
            Issue.record("expected storeSchemaIncoherent, got \(String(describing: thrown))")
            return
        }
        #expect(FileManager.default.fileExists(atPath: url.path), "her copy stays where it is")
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("incoherent").path))
        #expect(AssistantStartupProblem(thrown).canRebuild)
    }
}
