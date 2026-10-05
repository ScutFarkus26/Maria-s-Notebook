import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The app runs on two stores, as on a phone: the class in the shared store,
// and in the private store anything else the Apple Account keeps (a
// notebook of her own, say). The other suites use one in-memory store.
@Suite("Assistant on two stores")
@MainActor
struct AssistantSplitStoreTests {

    /// Private and shared SQLite stores in a temporary folder.
    private func splitContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            _ = try coordinator.addPersistentStore(
                type: .sqlite, configuration: configuration, at: dir.appendingPathComponent("\(configuration).sqlite")
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func store(_ configuration: String, in context: NSManagedObjectContext) throws -> NSPersistentStore {
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        return try #require(stores.first { $0.configurationName == configuration })
    }

    @Test("The shared store holds Restock's staples, their history and the needs (schema 15)")
    func sharedStoreTakesRestock() throws {
        let model = try CoreDataStack.sharedModel()
        let shared = Set(
            (model.entities(forConfigurationName: CoreDataStack.sharedConfiguration) ?? []).compactMap(\.name)
        )
        #expect(["Supply", "SupplyTransaction", "OrderItem"].allSatisfy(shared.contains))
        let context = try splitContext()
        let sharedStore = try store(CoreDataStack.sharedConfiguration, in: context)
        let staple = NSEntityDescription.insertNewObject(forEntityName: "Supply", into: context)
        staple.setValue(UUID(), forKey: "id")
        let history = NSEntityDescription.insertNewObject(forEntityName: "SupplyTransaction", into: context)
        history.setValue(UUID(), forKey: "id")
        history.setValue(staple, forKey: "supply")
        let need = NSEntityDescription.insertNewObject(forEntityName: "OrderItem", into: context)
        need.setValue(UUID(), forKey: "id")
        for row in [staple, history, need] { context.assign(row, to: sharedStore) }
        #expect(context.safeSave())
        #expect([staple, history, need].allSatisfy { $0.objectID.persistentStore == sharedStore })
    }

    @Test("Her name goes into the shared store, and names are read only from the classroom share (schema 16)")
    func namesLiveInTheShare() throws {
        let model = try CoreDataStack.sharedModel()
        let sharedTypes = model.entities(forConfigurationName: CoreDataStack.sharedConfiguration) ?? []
        #expect(sharedTypes.contains { $0.name == "ClassroomPerson" })
        let context = try splitContext()
        let sharedStore = try store(CoreDataStack.sharedConfiguration, in: context)
        let privateStore = try store(CoreDataStack.privateConfiguration, in: context)

        // A notebook of her own on the same Apple Account, where she's the guide.
        let ownNotebook = CDClassroomPerson(context: context)
        context.assign(ownNotebook, to: privateStore)
        ownNotebook.recordName = "_ana"
        ownNotebook.role = .leadGuide
        ownNotebook.displayName = "Ms. A"
        // Her guide's row, as the share brings it.
        let guide = CDClassroomPerson(context: context)
        context.assign(guide, to: sharedStore)
        guide.recordName = "_guide"
        guide.role = .leadGuide
        guide.displayName = "Danny"
        #expect(context.safeSave())

        let previous = (
            ClassroomIdentity.currentUserRecordName, ClassroomIdentity.displayName, ClassroomIdentity.nameWaitingAs
        )
        defer {
            ClassroomIdentity.currentUserRecordName = previous.0
            ClassroomIdentity.displayName = previous.1
            ClassroomIdentity.nameWaitingAs = previous.2
        }
        ClassroomIdentity.currentUserRecordName = "_ana"
        let written = try #require(ClassroomNames.setMyName("Ana", role: .assistant, in: context))
        #expect(written.isNew, "her notebook's row is another classroom's, not hers here")
        #expect(context.safeSave())
        #expect(written.person.objectID.persistentStore == sharedStore)

        let names = ClassroomNames.snapshot(in: context)
        #expect(names.guideName == "Danny")
        #expect(names.name(forRecordName: "_ana") == "Ana")
        #expect(ClassroomNames.guideName(in: context) == "Danny")
        #expect(ownNotebook.displayName == "Ms. A")
    }

    @Test("Only the classroom share's children are on the roll, and every mark goes to the shared store")
    func classroomOnly() throws {
        let context = try splitContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        let privateStore = try store(CoreDataStack.privateConfiguration, in: context)
        for first in ["Ari", "Maya"] {
            context.assign(AssistantTestSupport.student(first, "Cedar", in: context), to: shared)
        }
        // A child from a notebook of her own on the same Apple Account.
        context.assign(AssistantTestSupport.student("Zev", "Oak", in: context), to: privateStore)
        #expect(context.safeSave())

        let model = AssistantAttendanceViewModel(
            context: context, container: nil, date: Date(), defaults: AssistantTestSupport.makeDefaults()
        )
        model.load()
        #expect(model.rows.map(\.student.firstName) == ["Ari", "Maya"])

        model.tap(try #require(model.rows.first))
        #expect(model.beginLate() == 1)
        let records = context.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.objectID.persistentStore == shared })
    }
}
