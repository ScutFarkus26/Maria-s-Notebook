import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The background upkeep and the sync-change handler that feeds it: a burst of
// changes holds one background task and rebuilds the reminders once, and only
// a change that can take her membership away reads it again.
@Suite("Reminder upkeep and the sync-change handler")
@MainActor
struct ReminderUpkeepTests {

    /// What an upkeep under test did: background tasks begun, rebuilds run.
    @MainActor
    final class Spy {
        var keepAlives = 0
        var rebuilt: [NSManagedObjectContext] = []
    }

    private func upkeep(
        _ spy: Spy,
        rebuild: (@MainActor (NSManagedObjectContext) async -> Void)? = nil
    ) -> EarlyPickupReminderUpkeep {
        EarlyPickupReminderUpkeep(
            delay: .milliseconds(50),
            keepAlive: { _, work in
                spy.keepAlives += 1
                Task { await work() }
            },
            rebuild: { context in
                spy.rebuilt.append(context)
                await rebuild?(context)
            }
        )
    }

    /// Waits until `condition` holds, for up to 10 s.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test("A burst of 22 changes holds one background task and rebuilds once, with the latest context")
    func burstHoldsOneBackgroundTask() async throws {
        let earlier = try AssistantTestSupport.makeStack()
        let latest = try AssistantTestSupport.makeStack()
        let spy = Spy()
        let upkeep = upkeep(spy)

        for index in 0..<22 {
            let context = index == 21 ? latest.viewContext : earlier.viewContext
            upkeep.changed { context }
        }

        #expect(await eventually { spy.rebuilt.count == 1 })
        #expect(spy.keepAlives == 1)
        #expect(spy.rebuilt.first === latest.viewContext)
    }

    @Test("A change after the burst has settled gets a background task and a rebuild of its own")
    func laterChangeGetsItsOwnWindow() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let spy = Spy()
        let upkeep = upkeep(spy)

        upkeep.changed { context }
        #expect(await eventually { spy.rebuilt.count == 1 })
        upkeep.changed { context }
        #expect(await eventually { spy.rebuilt.count == 2 })
        #expect(spy.keepAlives == 2)
    }

    @Test("With no class to follow when the burst settles, nothing is rebuilt")
    func noClassNoRebuild() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let spy = Spy()
        let upkeep = upkeep(spy)

        upkeep.changed { context }
        upkeep.changed { nil }
        let settled = await eventually { spy.keepAlives == 1 && !upkeep.isWaiting }
        #expect(settled)
        #expect(spy.rebuilt.isEmpty)
    }

    @Test("Settled, a burst leaves the same reminders as one rebuild, reading each kind's pending requests once")
    func burstMatchesOneRebuild() async throws {
        let stack = try ReminderTestClass.withEmail()
        let context = stack.viewContext
        let reference = FakeReminderCenter()
        await EarlyPickupReminderUpkeep.refresh(in: context, isSample: false, center: reference)

        let center = FakeReminderCenter()
        let spy = Spy()
        let upkeep = upkeep(spy) { context in
            await EarlyPickupReminderUpkeep.refresh(in: context, isSample: false, center: center)
        }
        for _ in 0..<5 { upkeep.changed { context } }

        #expect(await eventually { spy.rebuilt.count == 1 && !center.ids("frontdesk-").isEmpty })
        #expect(center.ids("arrival-") == reference.ids("arrival-"))
        #expect(center.ids("frontdesk-") == reference.ids("frontdesk-"))
        // Pickups, arrival and front desk: one read each, for the one rebuild.
        #expect(center.pendingReads == 3)
    }

    // MARK: - Which changes read the membership again

    @Test("Only a change to the private store, or one from a store it can't name, reads her membership again")
    func membershipReadOnlyForThePrivateStore() {
        #expect(AssistantBootstrapper.mayChangeMembership(storeID: "private", privateStoreID: "private"))
        #expect(!AssistantBootstrapper.mayChangeMembership(storeID: "shared", privateStoreID: "private"))
        #expect(AssistantBootstrapper.mayChangeMembership(storeID: nil, privateStoreID: "private"))
        #expect(AssistantBootstrapper.mayChangeMembership(storeID: "shared", privateStoreID: nil))
    }

    @Test("Membership rows can only be in the private store, which is what the read's gate relies on")
    func membershipLivesInThePrivateStore() throws {
        let model = try CoreDataStack.sharedModel()
        let privateTypes = (model.entities(forConfigurationName: CoreDataStack.privateConfiguration) ?? [])
            .compactMap(\.name)
        let sharedTypes = (model.entities(forConfigurationName: CoreDataStack.sharedConfiguration) ?? [])
            .compactMap(\.name)
        #expect(privateTypes.contains("ClassroomMembership"))
        #expect(!sharedTypes.contains("ClassroomMembership"))

        // Saved with both stores open, the row goes to the private one.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            _ = try coordinator.addPersistentStore(
                type: .sqlite, configuration: configuration, at: dir.appendingPathComponent("\(configuration).sqlite")
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let row = CDClassroomMembership(context: context)
        row.role = .assistant
        #expect(context.safeSave())
        #expect(row.objectID.persistentStore?.configurationName == CoreDataStack.privateConfiguration)
    }

    @Test("While the sample is open, only its own saves skip the read for a real class arriving")
    func sampleSavesSkipTheRealClassRead() {
        #expect(!AssistantBootstrapper.mayBringRealClass(storeID: "sample", sampleStoreIDs: ["sample"]))
        #expect(AssistantBootstrapper.mayBringRealClass(storeID: "private", sampleStoreIDs: ["sample"]))
        #expect(AssistantBootstrapper.mayBringRealClass(storeID: nil, sampleStoreIDs: ["sample"]))
        #expect(AssistantBootstrapper.mayBringRealClass(storeID: "private", sampleStoreIDs: []))
    }
}
