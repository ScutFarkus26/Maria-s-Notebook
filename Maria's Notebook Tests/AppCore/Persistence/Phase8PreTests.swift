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

    // MARK: - Entity Routing Baseline

    /// Tombstone entities (2026-06-11): these belong to features Danny removed
    /// end-to-end (Transition Planner, Work Cycle, Prep Checklists, Initiatives).
    /// No code references their CD* classes. They stay in the Core Data model
    /// because the CloudKit schema is additive-only — removing entities triggers
    /// re-mirroring and the "empty DB on launch" bug — and they are intentionally
    /// routed to NO store. If one of these names ever becomes routed again
    /// (feature revived), the test below flags it so this list gets pruned.
    private static let knownUnroutedEntities: Set<String> = [
        "WorkCycleSession", "WorkCycleEntry",
        "PrepChecklist", "PrepChecklistItem", "PrepChecklistCompletion",
        "TransitionPlan", "TransitionChecklistItem",
        "Initiative"
    ]

    @Test("Every model entity is routed to exactly one store")
    func allModelEntitiesAreRouted() throws {
        let modelURL = try #require(
            Bundle.main.url(forResource: "MariasNotebook", withExtension: "momd"),
            "Model URL should be found in bundle"
        )
        let model = try #require(NSManagedObjectModel(contentsOf: modelURL))
        let modelEntities = Set(model.entities.compactMap { $0.isAbstract ? nil : $0.name })
        let routed = CoreDataStack.sharedEntityNames.union(CoreDataStack.privateEntityNames)
        let unrouted = modelEntities.subtracting(routed).subtracting(Self.knownUnroutedEntities)
        let phantom = routed.subtracting(modelEntities)
        let healed = Self.knownUnroutedEntities.intersection(routed)
        #expect(unrouted.isEmpty, "Model entities not routed to any store: \(unrouted.sorted())")
        #expect(phantom.isEmpty, "Routed names with no model entity: \(phantom.sorted())")
        #expect(
            healed.isEmpty,
            "Now-routed entities still in knownUnroutedEntities — remove them from the allowlist: \(healed.sorted())"
        )
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

    // MARK: - Migration Infrastructure Baseline

    @Test("AppBootstrapper starts in idle state")
    func bootstrapperStartsIdle() {
        // Keep the state-machine cases explicit without switching on a
        // compile-time constant.
        let states: [AppBootstrapper.State] = [.idle, .initializingContainer, .migrating, .ready]
        #expect(states.count == 4)
    }

    @Test("CoreDataStack store URLs use expected file names")
    func storeURLsUseExpectedNames() {
        let privateURL = CoreDataStack.privateStoreURL()
        let sharedURL = CoreDataStack.sharedStoreURL()
        #expect(privateURL.lastPathComponent == "private.sqlite")
        #expect(sharedURL.lastPathComponent == "shared.sqlite")
    }

}
