import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// An Apple Account change while a name saves (bug hunt 2026-10-09, #5, and
/// its review). A name typed under one account must never go into another's
/// row, so a save that finds another account signed in takes its name back,
/// and a name waiting is dropped once another account is confirmed. Until
/// then the account may come back the same, so the name keeps waiting, and
/// on the notebook the next import writes it.
@Suite("Classroom names: account changes during a save", .serialized)
@MainActor
struct ClassroomNamesAccountChangeTests {

    private typealias Support = ClassroomNamesTestSupport

    private func everyone(in context: NSManagedObjectContext) -> [CDClassroomPerson] {
        context.safeFetch(CDFetchRequest(CDClassroomPerson.self))
    }

    /// A lookup that answers at once that nothing has been sent.
    private let answering: @Sendable ([NSManagedObjectID]) -> [NSManagedObjectID: String] = { _ in [:] }

    /// Runs `body` with `during` run inside its first lookup's wait.
    private func whileLookingUp<T>(during: @escaping () async -> Void, _ body: () async -> T) async -> T {
        var ran = false
        let hook = ClassroomNames.LookupHook {
            guard !ran else { return }
            ran = true
            await during()
            // Lets any task started above reach its own wait first.
            for _ in 0..<5 { await Task.yield() }
        }
        return await ClassroomNames.$zoneLookupOverride.withValue(answering) {
            await ClassroomNames.$zoneLookupHook.withValue(hook) { await body() }
        }
    }

    /// His row, pinned in a classroom that's on this device, so a held write
    /// can run at the next import.
    private func guideInClass(
        _ context: NSManagedObjectContext, arrival: ClassroomNames.Arrival
    ) -> CDClassroomPerson {
        let row = Support.person("_guide", "Danny", role: .leadGuide, created: Support.at(0), in: context)
        let membership = CDClassroomMembership(context: context)
        membership.role = .leadGuide
        membership.classroomZoneID = "com.apple.coredata.cloudkit.share.NOW"
        #expect(context.safeSave())
        for store in context.persistentStoreCoordinator?.persistentStores ?? [] {
            arrival.noteImport(intoStoreWithIdentifier: store.identifier ?? "", startedAt: Date())
        }
        return row
    }

    // Review 2026-10-09: taking the name back while the account was unknown
    // lost a rename when the same account came back.
    @Test("An account read again during a save keeps the name waiting; the same one back, the next import writes it")
    func accountReadAgainDuringASave() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let arrival = ClassroomNames.Arrival()
        let row = guideInClass(context, arrival: arrival)

        await Support.asDevice(recordName: "_guide") {
            let set = await whileLookingUp(during: { ClassroomIdentity.currentUserRecordName = nil }, {
                await ClassroomNames.setMyName("Dan", role: .leadGuide, in: context, arrival: arrival)
            })
            if case .waiting = set {} else { Issue.record("expected the name to wait, got \(set)") }
            #expect(ClassroomIdentity.nameWaitingAs == .leadGuide)
            #expect(ClassroomIdentity.nameWaitingFor == "_guide", "typed under his account")
            #expect(ClassroomIdentity.displayName == "Dan")
            #expect(row.displayName == "Danny")

            ClassroomIdentity.currentUserRecordName = "_guide"
            await ClassroomNames.$zoneLookupOverride.withValue(answering) {
                arrival.noteImport(intoStoreWithIdentifier: "another", startedAt: Date())
                await arrival.importWork?.value
            }
            #expect(row.displayName == "Dan", "written once the same account is back")
            #expect(ClassroomIdentity.nameWaitingAs == nil)
            #expect(!context.hasChanges, "saved")
        }
    }

    @Test("Another account confirmed after a save kept its name waiting drops it, and nothing goes into its row")
    func anotherAccountConfirmedAfterTheSave() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let arrival = ClassroomNames.Arrival()
        let row = guideInClass(context, arrival: arrival)
        let (reread, readNow) = AsyncStream.makeStream(of: Void.self)
        var change: Task<Void, Never>?

        await Support.asDevice(recordName: "_guide") {
            // The account changes during the lookup, and is read after it ends.
            let set = await whileLookingUp(during: {
                change = Task {
                    await ClassroomIdentity.accountChanged {
                        for await _ in reread { break }
                        ClassroomIdentity.currentUserRecordName = "_bea"
                    }
                }
            }, {
                await ClassroomNames.setMyName("Dan", role: .leadGuide, in: context, arrival: arrival)
            })
            if case .waiting = set {} else { Issue.record("expected the name to wait, got \(set)") }
            readNow.yield()
            readNow.finish()
            await change?.value
            #expect(ClassroomIdentity.nameWaitingAs == nil, "dropped: _bea is another account")
            #expect(ClassroomIdentity.displayName == nil)

            await ClassroomNames.$zoneLookupOverride.withValue(answering) {
                arrival.noteImport(intoStoreWithIdentifier: "another", startedAt: Date())
                await arrival.importWork?.value
            }
            #expect(row.displayName == "Danny")
            #expect(everyone(in: context).map(\.recordName) == ["_guide"], "no row under _bea")
        }
    }

    // Review 2026-10-09: an account change nobody saw (it couldn't be read,
    // then the notebook opened under another) let the last account's name in.
    @Test("A waiting name goes in only under the account it was typed under; under another it's dropped")
    func waitingNameKeepsItsAccount() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let arrival = ClassroomNames.Arrival(waitsForTheClass: false)
        func write() async -> Bool {
            await ClassroomNames.writeWaitingName(role: .leadGuide, in: context, arrival: arrival)
        }

        // Typed under _guide; the notebook opens under _bea.
        await Support.asDevice(recordName: "_guide", displayName: "Danny") {
            ClassroomNames.markWaiting(as: .leadGuide)
            ClassroomIdentity.currentUserRecordName = "_bea"
            #expect(await !write())
            #expect(everyone(in: context).isEmpty, "nothing under _bea")
            #expect(ClassroomIdentity.nameWaitingAs == nil, "dropped")
            #expect(ClassroomIdentity.nameWaitingFor == nil)
            #expect(ClassroomIdentity.displayName == nil)
        }

        // Typed under _guide; it opens under _guide again.
        await Support.asDevice(recordName: "_guide", displayName: "Danny") {
            ClassroomNames.markWaiting(as: .leadGuide)
            #expect(await write())
            #expect(everyone(in: context).map(\.recordName) == ["_guide"])
            #expect(everyone(in: context).map(\.displayName) == ["Danny"])
            #expect(ClassroomIdentity.nameWaitingAs == nil)
        }

        // Typed before any account was known (or waiting from an older
        // build): it goes in under whoever is signed in, as before.
        await Support.asDevice(recordName: nil, displayName: "Bea") {
            ClassroomNames.markWaiting(as: .leadGuide)
            #expect(ClassroomIdentity.nameWaitingFor == nil)
            ClassroomIdentity.currentUserRecordName = "_bea"
            #expect(await write())
            #expect(ClassroomNames.name(forRecordName: "_bea", in: context) == "Bea")
        }
    }

    @Test("An account change read during a save drops the waiting name, and the save puts nothing back")
    func accountChangeReadDuringASave() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (set, waiting, name) = await whileLookingUp(during: {
            await ClassroomIdentity.accountChanged { ClassroomIdentity.currentUserRecordName = "_bea" }
        }, {
            await Support.asDevice(recordName: "_guide", displayName: "Dan") {
                // A rename from before, still waiting under _guide.
                ClassroomNames.markWaiting(as: .leadGuide)
                let set = await ClassroomNames.setMyName("Danny", role: .leadGuide, in: context)
                return (set, ClassroomIdentity.nameWaitingAs, ClassroomIdentity.displayName)
            }
        })
        if case .nothing = set {} else { Issue.record("expected nothing saved, got \(set)") }
        #expect(waiting == nil, "neither name waits for _bea")
        #expect(name == nil)
        #expect(everyone(in: context).isEmpty)
    }
}
