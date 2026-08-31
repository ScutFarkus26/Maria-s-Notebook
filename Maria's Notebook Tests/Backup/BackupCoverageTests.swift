import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

// MARK: - Backup Coverage Exhaustiveness
//
// These tests are the tripwire for the failure mode that produced format v18:
// a new Core Data entity ships, someone forgets to add it to the backup, and
// the gap is invisible until a restore silently drops the data months later.
//
// Names here are always *model entity names* (e.g. "CommunityTopic"), which is
// what the writer/importer and store-routing sets use — NOT Swift class names
// (CDCommunityTopicEntity), which differ for @objc-renamed entities.

@Suite("Backup coverage exhaustiveness")
@MainActor
final class BackupCoverageTests {

    /// Entities that live in a store (so they pass the routing test) but are
    /// intentionally NOT backed up. Each is dormant or deprecated: it has no
    /// DTO, no transformer, no importer, and no app code that creates it.
    ///
    /// - `ProjectAssignmentTemplate`, `ProjectTemplateWeek`,
    ///   `ProjectWeekRoleAssignment`: deprecated project-template entities
    ///   (see the "deprecated" note in BackupService+Restoration importProjectEntities).
    /// - `SupplyTransaction`: entity definition with no DTO and no creation
    ///   site anywhere in the app — dormant schema only.
    ///
    /// If a NEW entity appears here, that's the signal to either back it up or
    /// consciously add it with a rationale. Removing one (by adding real backup
    /// coverage) is the happy path.
    private static let routedButIntentionallyNotBackedUp: Set<String> = [
        "ProjectAssignmentTemplate",
        "ProjectTemplateWeek",
        "ProjectWeekRoleAssignment",
        "SupplyTransaction"
    ]

    /// Model entities routed to NEITHER store. Every other coverage test here
    /// starts from the routing sets, so an unrouted entity escapes all of them:
    /// it can't persist (no store configuration includes it), it isn't backed
    /// up, and no tripwire fires. Each entry is dormant schema only — no Swift
    /// code references its class (CDInitiative, CDPrepChecklist, ...).
    ///
    /// If a NEW entity appears in the failure output, route it in
    /// CoreDataStack.sharedEntityNames/privateEntityNames (and back it up or
    /// add it to routedButIntentionallyNotBackedUp) — or consciously add it
    /// here with a rationale. Removing one (by wiring it up) is the happy path.
    private static var unroutedKnownDormant: Set<String> {
        CoreDataStack.dormantTombstoneEntities
    }

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    /// Registry entity types mapped to their MODEL names (the same resolution
    /// the backup system itself uses), skipping any not present in the model.
    private func registryModelNames(in context: NSManagedObjectContext) -> Set<String> {
        Set(BackupEntityRegistry.allTypes.compactMap {
            BackupFetchHelper.entityName(for: $0, in: context)
        })
    }

    @Test("Writer and importer cover exactly the same entity set")
    func writerMatchesImporter() {
        let writer = Set(BackupWriter.serializedEntityNames)
        let importer = Set(BackupImporter.handledEntityNames)

        let onlyWriter = writer.subtracting(importer)
        let onlyImporter = importer.subtracting(writer)
        #expect(onlyWriter.isEmpty, "Entities written but never read back: \(onlyWriter.sorted())")
        #expect(onlyImporter.isEmpty, "Entities read but never written: \(onlyImporter.sorted())")
    }

    @Test("Writer's serialization table has no duplicate entity names")
    func writerHasNoDuplicates() {
        let names = BackupWriter.serializedEntityNames
        #expect(names.count == Set(names).count, "BackupWriter.serializedEntityNames has duplicates: \(names)")
    }

    @Test("Every backed-up entity name is a real, routed model entity")
    func writerNamesAreRoutedModelEntities() {
        let writer = Set(BackupWriter.serializedEntityNames)
        let routed = CoreDataStack.sharedEntityNames.union(CoreDataStack.privateEntityNames)

        let unrouted = writer.subtracting(routed)
        #expect(
            unrouted.isEmpty,
            "Writer serializes names that aren't routed to any store (typo or stale name?): \(unrouted.sorted())"
        )
    }

    @Test("Registry, writer, and importer agree on the backed-up entity set")
    func registryMatchesWriterAndImporter() throws {
        let context = try makeContext()
        let registry = registryModelNames(in: context)
        let writer = Set(BackupWriter.serializedEntityNames)

        let registryNotInWriter = registry.subtracting(writer)
        #expect(
            registryNotInWriter.isEmpty,
            "Registry entities missing from BackupWriter (export would drop them): \(registryNotInWriter.sorted())"
        )

        let writerNotInRegistry = writer.subtracting(registry).sorted()
        #expect(
            writerNotInRegistry.isEmpty,
            "Writer entities missing from the registry (replace-mode wouldn't clear them): \(writerNotInRegistry)"
        )
    }

    @Test("Every entity routed to a store is backed up or explicitly excluded")
    func everyRoutedEntityIsBackedUpOrExcluded() {
        let routed = CoreDataStack.sharedEntityNames.union(CoreDataStack.privateEntityNames)
        let backedUp = Set(BackupWriter.serializedEntityNames)

        let gap = routed.subtracting(backedUp).subtracting(Self.routedButIntentionallyNotBackedUp)
        let gapList = gap.sorted()
        // A non-empty gap means a routed entity has no DTO/writer/importer and
        // isn't on the exclusion list — back it up or document why not.
        #expect(gap.isEmpty, "Routed entities not backed up and not excluded: \(gapList)")
    }

    @Test("Every model entity is routed to a store or explicitly known-dormant")
    func everyModelEntityIsRoutedOrKnownDormant() throws {
        let context = try makeContext()
        let model = try #require(
            context.persistentStoreCoordinator?.managedObjectModel,
            "In-memory stack should expose its managed object model"
        )
        let modelNames = Set(model.entities.compactMap(\.name))
        let routed = CoreDataStack.sharedEntityNames.union(CoreDataStack.privateEntityNames)

        let unrouted = modelNames.subtracting(routed).subtracting(Self.unroutedKnownDormant)
        // A non-empty set means a model entity is invisible to every other
        // coverage test in this suite — route it and back it up (or exclude
        // it), or document it as dormant.
        #expect(unrouted.isEmpty, "Model entities routed to no store and not known-dormant: \(unrouted.sorted())")
    }

    @Test("Dormant list stays honest: each entry is in the model and still unrouted")
    func dormantListIsNotStale() throws {
        let context = try makeContext()
        let model = try #require(
            context.persistentStoreCoordinator?.managedObjectModel,
            "In-memory stack should expose its managed object model"
        )
        let modelNames = Set(model.entities.compactMap(\.name))
        let routed = CoreDataStack.sharedEntityNames.union(CoreDataStack.privateEntityNames)

        for dormant in Self.unroutedKnownDormant {
            #expect(
                modelNames.contains(dormant),
                "Dormant entry '\(dormant)' is no longer in the model — remove it from the dormant list"
            )
            #expect(
                !routed.contains(dormant),
                "Dormant entry '\(dormant)' is now routed to a store — remove it from the dormant list"
            )
        }
    }

    @Test("Exclusion list stays honest: each entry is routed and still unbacked")
    func exclusionListIsNotStale() {
        let routed = CoreDataStack.sharedEntityNames.union(CoreDataStack.privateEntityNames)
        let backedUp = Set(BackupWriter.serializedEntityNames)

        for excluded in Self.routedButIntentionallyNotBackedUp {
            #expect(
                routed.contains(excluded),
                "Exclusion '\(excluded)' is no longer routed to a store — remove it from the exclusion list"
            )
            #expect(
                !backedUp.contains(excluded),
                "Exclusion '\(excluded)' is now backed up — remove it from the exclusion list"
            )
        }
    }
}
