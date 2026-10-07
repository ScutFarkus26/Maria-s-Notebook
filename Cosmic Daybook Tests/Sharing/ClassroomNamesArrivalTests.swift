import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A waiting name is written, and duplicate rows folded, only once the class is
/// on this device: a membership, and this launch's first import into the
/// person's store since it was pinned (2026-10-05 sync and sharing hunt). And
/// the guide's name is the owner's row only. Imports are handed to the arrival
/// by hand (`noteImport`), as CloudKit's events would.
@Suite("Classroom names: waiting for the class", .serialized)
@MainActor
struct ClassroomNamesArrivalTests {

    private typealias Support = ClassroomNamesTestSupport

    private let classroom = "com.apple.coredata.cloudkit.share.NOW"
    private let lastClassroom = "com.apple.coredata.cloudkit.share.BEFORE"

    private func at(_ seconds: TimeInterval) -> Date {
        Support.at(seconds)
    }

    private func pin(
        _ role: CDClassroomMembership.ClassroomRole,
        at time: Date,
        owner: String = "",
        in context: NSManagedObjectContext
    ) {
        let membership = CDClassroomMembership(context: context)
        membership.role = role
        membership.classroomZoneID = classroom
        membership.ownerIdentity = owner
        membership.joinedAt = time
        membership.modifiedAt = time
    }

    private func store(
        _ configuration: String, in context: NSManagedObjectContext
    ) throws -> NSPersistentStore {
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        return try #require(stores.first { $0.configurationName == configuration })
    }

    private func rows(_ recordName: String, in context: NSManagedObjectContext) -> [CDClassroomPerson] {
        let request = CDFetchRequest(CDClassroomPerson.self)
        request.predicate = NSPredicate(format: "recordName == %@", recordName)
        return context.safeFetch(request)
    }

    // MARK: - Waiting for the class

    @Test("Her name waits until she is in a class and it has come down, then goes in by itself")
    func assistantNameWaitsForHerClass() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        let sharedID = try #require(shared.identifier)
        let arrival = ClassroomNames.Arrival()
        var created: [NSManagedObject] = []

        await Support.asDevice(recordName: "_ana", displayName: "Ana") {
            let wrote = await ClassroomNames.writeWaitingName(
                role: .assistant, in: context, arrival: arrival
            ) { context, new in
                created += new
                return context.safeSave()
            }
            #expect(!wrote, "no class yet")
            #expect(rows("_ana", in: context).isEmpty)

            // She joins at 100. An import that began before brought no class.
            pin(.assistant, at: at(100), in: context)
            #expect(context.safeSave())
            arrival.noteImport(intoStoreWithIdentifier: sharedID, startedAt: at(90))
            await arrival.importWork?.value
            #expect(rows("_ana", in: context).isEmpty)

            // The one that began after she joined did: the held write runs.
            arrival.noteImport(intoStoreWithIdentifier: sharedID, startedAt: at(110))
            await arrival.importWork?.value
            let row = rows("_ana", in: context).first
            #expect(row?.displayName == "Ana")
            #expect(row?.objectID.persistentStore == shared)
            #expect(created.map(\.objectID) == row.map { [$0.objectID] }, "handed to the save, into the share")
            #expect(!context.hasChanges)
        }
    }

    @Test("The launch fold waits for this launch's first import into his own store")
    func guideFoldWaitsForHisImport() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let privateStore = try store(CoreDataStack.privateConfiguration, in: context)
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        pin(.leadGuide, at: at(100), in: context)
        let oldest = Support.person(
            "_guide", "Danny", role: .leadGuide, created: at(0), modified: at(10), store: privateStore, in: context
        )
        Support.person(
            "_guide", "Daniel", role: .leadGuide, created: at(50), modified: at(60), store: privateStore, in: context
        )
        #expect(context.safeSave())
        let arrival = ClassroomNames.Arrival()

        await Support.asDevice(recordName: "_guide") {
            #expect(await !ClassroomNames.writeWaitingName(in: context, arrival: arrival))
            #expect(rows("_guide", in: context).count == 2, "nothing folded before this launch's import")

            // An import into the other store says nothing about his rows.
            arrival.noteImport(intoStoreWithIdentifier: shared.identifier ?? "", startedAt: at(110))
            await arrival.importWork?.value
            #expect(rows("_guide", in: context).count == 2)

            arrival.noteImport(intoStoreWithIdentifier: privateStore.identifier ?? "", startedAt: at(120))
            await arrival.importWork?.value
            #expect(rows("_guide", in: context).map(\.id) == [oldest.id], "folded into the oldest row")
            #expect(oldest.displayName == "Daniel", "carrying the newest name")
            #expect(!context.hasChanges, "saved")
        }
    }

    @Test("A fold as an import finishes carries the rename it brought, not the context's older copy")
    func foldReadsTheStoreNotAnOlderCopy() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        pin(.leadGuide, at: at(100), in: context)
        let oldest = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(10), in: context)
        Support.person("_guide", "Dan", role: .leadGuide, created: at(50), modified: at(60), in: context)
        #expect(context.safeSave())

        // The import renames his oldest row through another context; this one
        // hasn't merged it yet.
        let importer = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        importer.persistentStoreCoordinator = context.persistentStoreCoordinator
        let imported = try #require(try importer.existingObject(with: oldest.objectID) as? CDClassroomPerson)
        imported.displayName = "Daniel"
        imported.modifiedAt = at(70)
        #expect(importer.safeSave())
        #expect(oldest.displayName == "Danny", "the view context still holds its older copy")

        let arrival = ClassroomNames.Arrival()
        for store in context.persistentStoreCoordinator?.persistentStores ?? [] {
            arrival.noteImport(intoStoreWithIdentifier: store.identifier ?? "", startedAt: at(110))
        }
        await Support.asDevice(recordName: "_guide") {
            #expect(await ClassroomNames.writeWaitingName(in: context, arrival: arrival))
        }
        #expect(rows("_guide", in: context).map(\.id) == [oldest.id])
        #expect(oldest.displayName == "Daniel", "the rename stands; the older 'Dan' never goes up over it")
    }

    @Test("A write held for one Apple Account is dropped once another signs in")
    func heldWriteDroppedForAnotherAccount() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        let arrival = ClassroomNames.Arrival()

        await Support.asDevice(recordName: "_ana", displayName: "Ana") {
            #expect(await !ClassroomNames.writeWaitingName(role: .assistant, in: context, arrival: arrival))
        }
        pin(.assistant, at: at(100), in: context)
        #expect(context.safeSave())
        await Support.asDevice(recordName: "_bea", displayName: "Ana") {
            arrival.noteImport(intoStoreWithIdentifier: shared.identifier ?? "", startedAt: at(110))
            await arrival.importWork?.value
        }
        #expect(context.safeFetch(CDFetchRequest(CDClassroomPerson.self)).isEmpty)
    }

    @Test("Once the class is here a waiting name is written at once")
    func classAlreadyHere() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        pin(.assistant, at: at(100), in: context)
        #expect(context.safeSave())
        let arrival = ClassroomNames.Arrival()
        arrival.noteImport(intoStoreWithIdentifier: shared.identifier ?? "", startedAt: at(110))

        await Support.asDevice(recordName: "_ana", displayName: "Ana") {
            #expect(await ClassroomNames.writeWaitingName(role: .assistant, in: context, arrival: arrival))
        }
        #expect(ClassroomNames.name(forRecordName: "_ana", in: context) == "Ana")
    }

    // MARK: - The guide's name

    @Test("An owner who hasn't named himself has no name, never another class's guide")
    func ownerWithoutARow() throws {
        let context = try CoreDataTestHelpers.makeContext()
        pin(.assistant, at: at(100), owner: "_guide", in: context)
        Support.person("_oldGuide", "Mr. Cole", role: .leadGuide, created: at(0), modified: at(500), in: context)
        #expect(context.safeSave())

        let names = ClassroomNames.snapshot(in: context)
        #expect(names.guideName == nil)
        #expect(names.fallingBack(toGuideName: "Danny D").guideName == "Danny D", "Apple's name for the owner")

        Support.person("_guide", "Danny", role: .leadGuide, created: at(600), in: context)
        #expect(context.safeSave())
        #expect(ClassroomNames.snapshot(in: context).guideName == "Danny")
    }

    @Test("On the guide's own devices his row is the guide's, whatever other guides' rows the stores hold")
    func guidesOwnDevices() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // A class he is an assistant in, kept in his shared store.
        Support.person("_other", "Ms. Lee", role: .leadGuide, created: at(0), modified: at(500), in: context)
        #expect(context.safeSave())

        Support.asDevice(recordName: "_guide") {
            #expect(ClassroomNames.snapshot(in: context).guideName == nil, "he hasn't named himself")
            Support.person("_guide", "Danny", role: .leadGuide, created: at(10), in: context)
            #expect(context.safeSave())
            #expect(ClassroomNames.snapshot(in: context).guideName == "Danny")
        }
    }

    @Test("With the owner unknown, only guides in the pinned classroom count")
    func unknownOwnerKeepsToThePinnedClassroom() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        pin(.assistant, at: at(100), owner: "unknown", in: context)
        let before = Support.person(
            "_oldGuide", "Mr. Cole", role: .leadGuide, created: at(0), modified: at(500), in: context
        )
        let now = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(10), in: context)
        #expect(context.safeSave())
        let zones = [before.objectID: lastClassroom, now.objectID: classroom]
        let lookup: @Sendable ([NSManagedObjectID]) -> [NSManagedObjectID: String] = { _ in zones }

        // The read never asks iCloud: it uses the zones the warm-up looked up.
        let guideName = await ClassroomNames.$zoneLookupOverride.withValue(lookup) {
            await ClassroomNames.warmZones(in: context, arrival: nil)
            return ClassroomNames.snapshot(in: context).guideName
        }
        #expect(guideName == "Danny")
    }
}
