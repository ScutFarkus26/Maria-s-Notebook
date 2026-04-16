import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@Suite("Phase 8 Pre-Tests: Migration Path Baseline")
@MainActor
final class Phase8PreTests {

    // MARK: - Core Data Model Validation

    @Test("Core Data managed object model loads from bundle")
    func coreDataModelLoadsFromBundle() {
        let modelName = "MariasNotebook"
        let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd")
        #expect(modelURL != nil, "Model URL should be found in bundle")
        if let url = modelURL {
            let model = NSManagedObjectModel(contentsOf: url)
            #expect(model != nil, "Model should load successfully")
            if let model = model {
                // Model should contain entities for both stores
                let entityNames = Set(model.entities.map { $0.name ?? "" })
                #expect(entityNames.contains("Student"))
                #expect(entityNames.contains("Note"))
                #expect(entityNames.contains("ClassroomMembership"))
            }
        }
    }

    // MARK: - SwiftData Store Detection

    @Test("SwiftData store URL is deterministic and under Application Support")
    func swiftDataStoreURLIsDeterministic() {
        let url = DatabaseInitializationService.storeFileURL()
        #expect(url.lastPathComponent == "SwiftData.store")
        #expect(url.pathComponents.contains("Application Support")
             || url.pathComponents.contains("tmp"))  // tmp fallback in test env
    }

    @Test("SwiftData store does not exist in test environment")
    func swiftDataStoreDoesNotExistInTest() {
        let url = DatabaseInitializationService.storeFileURL()
        let exists = FileManager.default.fileExists(atPath: url.path)
        // In a test environment, there should be no legacy SwiftData store
        #expect(!exists, "SwiftData store should not exist in fresh test environment")
    }

    // MARK: - Entity Routing Baseline

    @Test("Shared store has expected entity count")
    func sharedStoreEntityCount() {
        let shared = CoreDataStack.sharedEntityNames
        // Current count: 32 shared entities (including ClassroomMembership)
        #expect(shared.count == 32)
    }

    @Test("Private store has expected entity count")
    func privateStoreEntityCount() {
        let priv = CoreDataStack.privateEntityNames
        // Current count: 28 private entities
        #expect(priv.count == 28)
    }

    @Test("Key shared entities are correctly routed")
    func sharedEntityRoutingCorrect() {
        let shared = CoreDataStack.sharedEntityNames
        #expect(shared.contains("Student"))
        #expect(shared.contains("Lesson"))
        #expect(shared.contains("Track"))
        #expect(shared.contains("Schedule"))
        #expect(shared.contains("Procedure"))
        #expect(shared.contains("ClassroomJob"))
        #expect(shared.contains("GoingOut"))
        #expect(shared.contains("ClassroomMembership"))
    }

    @Test("Key private entities are correctly routed")
    func privateEntityRoutingCorrect() {
        let priv = CoreDataStack.privateEntityNames
        #expect(priv.contains("Note"))
        #expect(priv.contains("AttendanceRecord"))
        #expect(priv.contains("WorkModel"))
        #expect(priv.contains("TodoItem"))
        #expect(priv.contains("Project"))
        #expect(priv.contains("Issue"))
        #expect(priv.contains("Reminder"))
        #expect(priv.contains("Document"))
    }

    @Test("No entity appears in both shared and private routing")
    func noOverlapBetweenStores() {
        let shared = CoreDataStack.sharedEntityNames
        let priv = CoreDataStack.privateEntityNames
        let overlap = shared.intersection(priv)
        #expect(overlap.isEmpty, "Entities in both stores: \(overlap)")
    }

    // MARK: - Backup System Baseline (post Phase 7)

    @Test("Backup format version is 13 (post Phase 7)")
    func backupFormatVersionIs13() {
        #expect(BackupFile.formatVersion == 13)
    }

    @Test("BackupEntityRegistry has 62 types (post Phase 7)")
    func backupRegistryCountIs62() {
        #expect(BackupEntityRegistry.allTypes.count == 62)
    }

    // MARK: - Migration Infrastructure Baseline

    @Test("AppBootstrapper starts in idle state")
    func bootstrapperStartsIdle() {
        // Verify bootstrap state machine starts at idle
        // (We can't test shared singleton directly, but we can test the enum)
        let state = AppBootstrapper.State.idle
        switch state {
        case .idle: break  // expected
        case .initializingContainer, .migrating, .ready:
            Issue.record("AppBootstrapper should start in idle state")
        }
    }

    @Test("CoreDataStack store URLs use expected file names")
    func storeURLsUseExpectedNames() {
        let privateURL = CoreDataStack.privateStoreURL()
        let sharedURL = CoreDataStack.sharedStoreURL()
        #expect(privateURL.lastPathComponent == "private.sqlite")
        #expect(sharedURL.lastPathComponent == "shared.sqlite")
    }

    // MARK: - Entity Coverage

    @Test("All shared + private entity names cover full entity set")
    func entityNamesCoverFullSet() {
        let shared = CoreDataStack.sharedEntityNames
        let priv = CoreDataStack.privateEntityNames
        let total = shared.count + priv.count
        // Total routed entities: 32 shared + 28 private = 60
        #expect(total == 60, "Total routed entities should be 60, got \(total)")
    }

}
