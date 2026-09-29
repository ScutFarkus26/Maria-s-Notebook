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
