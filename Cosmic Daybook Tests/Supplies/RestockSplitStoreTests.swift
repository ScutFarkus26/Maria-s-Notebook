import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Where Restock's new records land with both stores loaded, as on a device:
/// an assistant's go into the shared store, where the classroom share is (the
/// Assistant then attaches them through `AssistantSave`); the guide's into the
/// private store, from which `SharedStoreOrphanGuard` shares them.
@Suite("Restock on two stores", .serialized)
@MainActor
struct RestockSplitStoreTests {

    private let guide = RestockTestSupport.guide
    private let ana = RestockTestSupport.ana

    private struct Split {
        let context: NSManagedObjectContext
        let privateStore: NSPersistentStore
        let sharedStore: NSPersistentStore
        let directory: URL
    }

    /// Private and shared SQLite stores in a temporary folder.
    private func makeSplit() throws -> Split {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("restock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            _ = try coordinator.addPersistentStore(
                type: .sqlite, configuration: configuration,
                at: directory.appendingPathComponent("\(configuration).sqlite")
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let stores = coordinator.persistentStores
        return Split(
            context: context,
            privateStore: try #require(stores.first { $0.configurationName == CoreDataStack.privateConfiguration }),
            sharedStore: try #require(stores.first { $0.configurationName == CoreDataStack.sharedConfiguration }),
            directory: directory
        )
    }

    @Test("An assistant's staple, need and history go into the shared store")
    func assistantWritesToTheShare() throws {
        let split = try makeSplit()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let context = split.context

        let soap = try #require(RestockService.addStaple(
            .init(name: "Hand Soap", place: "Sink"), level: .low, by: ana, in: context
        )).object
        let glue = try #require(RestockService.addOneOff(title: "Glue sticks", by: ana, in: context)).object
        #expect(context.safeSave())

        let need = try #require(RestockService.openNeeds(for: soap, in: context).first)
        let history = try #require(RestockService.history(for: soap, in: context).first)
        for object in [soap, need, history, glue] as [NSManagedObject] {
            #expect(object.objectID.persistentStore == split.sharedStore, "\(object.entity.name ?? "")")
        }
    }

    @Test("A staple's need and history go beside it, whoever marks it")
    func levelOnASharedStaple() throws {
        let split = try makeSplit()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let context = split.context

        // The guide's staple as it arrives on an assistant's phone: in the share.
        let towels = CDSupply(context: context)
        towels.name = "Paper Towels"
        context.assign(towels, to: split.sharedStore)
        #expect(context.safeSave())

        // By role the guide's records go private; beside a shared staple they can't.
        #expect(RestockService.setLevel(towels, to: .out, by: guide, in: context))
        #expect(context.safeSave())
        let need = try #require(RestockService.openNeeds(for: towels, in: context).first)
        #expect(need.objectID.persistentStore == split.sharedStore)
        #expect(RestockService.history(for: towels, in: context).allSatisfy {
            $0.objectID.persistentStore == split.sharedStore
        })

        let checkOff = try #require(RestockService.checkOff(need, by: ana, in: context))
        #expect(context.safeSave())
        #expect(checkOff.history?.objectID.persistentStore == split.sharedStore)
        #expect(towels.level == .stocked)
    }

    @Test("The guide's records go into the private store")
    func guideWritesPrivately() throws {
        let split = try makeSplit()
        defer { try? FileManager.default.removeItem(at: split.directory) }
        let context = split.context

        let paper = try #require(RestockService.addStaple(
            .init(name: "Toilet Paper"), level: .out, by: guide, in: context
        )).object
        let hub = try #require(RestockService.addOneOff(
            title: "USB hub", link: URL(string: "https://www.example.com/hub"), by: guide, in: context
        )).object
        #expect(context.safeSave())
        let need = try #require(RestockService.openNeeds(for: paper, in: context).first)
        for object in [paper, need, hub] as [NSManagedObject] {
            #expect(object.objectID.persistentStore == split.privateStore, "\(object.entity.name ?? "")")
        }
        // Reading one store sees only that store's staples, as the Assistant reads the share.
        #expect(RestockService.staples(in: context, store: split.sharedStore).isEmpty)
        #expect(RestockService.staples(in: context, store: split.privateStore).map(\.name) == ["Toilet Paper"])
    }
}
