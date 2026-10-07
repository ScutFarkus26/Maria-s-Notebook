import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Each person sets their own name once and can change it; every screen looks
// names up by a stamp's record name when it words a line, so a rename reaches
// old entries (docs/Plans/Plan - Names you set yourself.md).
@Suite("Classroom names: the shared list", .serialized)
@MainActor
struct ClassroomNamesTests {

    private typealias Support = ClassroomNamesTestSupport

    private func at(_ seconds: TimeInterval) -> Date {
        Support.at(seconds)
    }

    private func everyone(in context: NSManagedObjectContext) -> [CDClassroomPerson] {
        context.safeFetch(CDFetchRequest(CDClassroomPerson.self))
    }

    // MARK: - Writing your own name

    @Test("Setting your name makes your row; setting it again changes that row")
    func upsertByRecordName() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        try await Support.asDevice(recordName: "_guide") {
            let first = try #require(
                await ClassroomNames.setMyName("Danny", role: .leadGuide, now: at(0), in: context).written
            )
            #expect(first.isNew)
            #expect(context.safeSave())
            let again = try #require(
                await ClassroomNames.setMyName("  Daniel ", role: .leadGuide, now: at(60), in: context).written
            )
            #expect(!again.isNew)
            #expect(again.person.objectID == first.person.objectID)
            #expect(context.safeSave())
        }
        let rows = everyone(in: context)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.recordName == "_guide")
        #expect(row.role == .leadGuide)
        #expect(row.displayName == "Daniel")
        #expect(row.createdAt == at(0))
        #expect(row.modifiedAt == at(60))

        // Another record name is another person's row.
        await Support.asDevice(recordName: "_ana") {
            let ana = await ClassroomNames.setMyName("Ana", role: .assistant, now: at(90), in: context)
            #expect(ana.written?.isNew == true)
            #expect(context.safeSave())
        }
        #expect(everyone(in: context).count == 2)
        #expect(ClassroomNames.name(forRecordName: "_guide", in: context) == "Daniel")
        #expect(ClassroomNames.name(forRecordName: "_ana", in: context) == "Ana")
    }

    @Test("Setting the same name again changes nothing")
    func sameNameIsNoChange() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        await Support.asDevice(recordName: "_guide") {
            await ClassroomNames.setMyName("Danny", role: .leadGuide, now: at(0), in: context)
            #expect(context.safeSave())
            await ClassroomNames.setMyName("Danny", role: .leadGuide, now: at(60), in: context)
            #expect(!context.hasChanges)
        }
        #expect(everyone(in: context).first?.modifiedAt == at(0))
    }

    @Test("Of two rows for one person, the newest name is the one read")
    func newestNameWins() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // His Mac's row and his iPad's, each written before the other arrived.
        Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(100), in: context)
        Support.person("_guide", "Dan", role: .leadGuide, created: at(10), modified: at(50), in: context)
        #expect(context.safeSave())
        #expect(ClassroomNames.name(forRecordName: "_guide", in: context) == "Danny")
        #expect(ClassroomNames.snapshot(in: context).name(forRecordName: "_guide") == "Danny")
        #expect(ClassroomNames.guideName(in: context) == "Danny")
    }

    @Test("Folding keeps the same row on either device, carrying the newest name")
    func foldSurvivorIsTheSameEverywhere() async throws {
        let macRowID = UUID()
        let iPadRowID = UUID()
        var survivors: [UUID?] = []
        // Each device holds both rows, having seen them arrive in either order.
        // The Mac's row is older; the iPad's carries the newer name.
        for arrivalOrder in [[true, false], [false, true]] {
            let context = try CoreDataTestHelpers.makeContext()
            for isMac in arrivalOrder {
                Support.person(
                    "_guide", isMac ? "Danny" : "Daniel", role: .leadGuide,
                    created: at(isMac ? 0 : 5), modified: at(isMac ? 10 : 90), id: isMac ? macRowID : iPadRowID,
                    in: context
                )
            }
            // An assistant's duplicate rows are hers to fold, not his.
            Support.person("_ana", "Ana", role: .assistant, created: at(0), in: context)
            Support.person("_ana", "Ana", role: .assistant, created: at(1), in: context)
            #expect(context.safeSave())

            await Support.asDevice(recordName: "_guide") {
                #expect(await ClassroomNames.foldMyRows(role: .leadGuide, in: context) == 1)
            }
            #expect(context.safeSave())
            let his = everyone(in: context).filter { $0.recordName == "_guide" }
            #expect(his.count == 1)
            #expect(his.first?.displayName == "Daniel")
            #expect(his.first?.modifiedAt == at(90))
            survivors.append(his.first?.id)
            #expect(everyone(in: context).filter { $0.recordName == "_ana" }.count == 2)
        }
        #expect(survivors == [macRowID, macRowID], "the oldest by (createdAt, id), whatever order the rows arrived in")
    }

    @Test("Clearing your name keeps your row, with no name in it")
    func clearingStoresAnEmptyName() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        try await Support.asDevice(recordName: "_guide") {
            await ClassroomNames.setMyName("Danny", role: .leadGuide, now: at(0), in: context)
            #expect(context.safeSave())
            let cleared = try #require(
                await ClassroomNames.setMyName("   ", role: .leadGuide, now: at(60), in: context).written
            )
            #expect(!cleared.isNew)
            #expect(context.safeSave())
            #expect(ClassroomNames.myName(role: .leadGuide, in: context) == "")
        }
        let rows = everyone(in: context)
        #expect(rows.count == 1)
        #expect(rows.first?.displayName == "")
        #expect(ClassroomNames.name(forRecordName: "_guide", in: context) == nil)
        #expect(ClassroomNames.guideName(in: context) == nil)

        // With no row yet, there's nothing to clear.
        await Support.asDevice(recordName: "_ana") {
            #expect(await ClassroomNames.setMyName(nil, role: .assistant, in: context).written == nil)
        }
        #expect(everyone(in: context).count == 1)
    }

    // MARK: - Reading

    @Test("The guide's name is the lead guide's row, never an assistant's; Apple's only when he typed none")
    func guideLookup() throws {
        let context = try CoreDataTestHelpers.makeContext()
        Support.person("_ana", "Ana", role: .assistant, created: at(0), in: context)
        #expect(context.safeSave())
        #expect(ClassroomNames.guideName(in: context) == nil)

        Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(5), in: context)
        #expect(context.safeSave())
        let names = ClassroomNames.snapshot(in: context)
        #expect(names.guideName == "Danny")
        #expect(names.role(forRecordName: "_ana") == .assistant)
        #expect(names.role(forRecordName: "_guide") == .leadGuide)
        #expect(names.name(forRecordName: "_nobody") == nil)
        #expect(names.name(forRecordName: CKCurrentUserDefaultName) == nil)

        #expect(names.fallingBack(toGuideName: "Danny D").guideName == "Danny")
        let unnamed = ClassroomNames.Snapshot()
        #expect(unnamed.fallingBack(toGuideName: "Danny D").guideName == "Danny D")
        #expect(unnamed.fallingBack(toGuideName: "  ").guideName == nil)
    }

    @Test("The guide's row goes to the private store, an assistant's to the shared store; each touches only their own")
    func storeScoping() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        let privateStore = try #require(stores.first { $0.configurationName == CoreDataStack.privateConfiguration })
        let sharedStore = try #require(stores.first { $0.configurationName == CoreDataStack.sharedConfiguration })

        try await Support.asDevice(recordName: "_guide") {
            let guide = try #require(await ClassroomNames.setMyName("Danny", role: .leadGuide, in: context).written)
            #expect(context.safeSave())
            #expect(guide.person.objectID.persistentStore == privateStore)
        }
        try await Support.asDevice(recordName: "_ana") {
            let ana = try #require(await ClassroomNames.setMyName("Ana", role: .assistant, in: context).written)
            #expect(context.safeSave())
            #expect(ana.person.objectID.persistentStore == sharedStore)
        }

        // The same Apple Account as an assistant in someone else's classroom:
        // that row is in the shared store, and his name as guide never touches it.
        let elsewhere = Support.person(
            "_guide", "Mr. D", role: .assistant, created: at(0), store: sharedStore, in: context
        )
        #expect(context.safeSave())
        try await Support.asDevice(recordName: "_guide") {
            let renamed = try #require(await ClassroomNames.setMyName("Daniel", role: .leadGuide, in: context).written)
            #expect(!renamed.isNew)
            #expect(renamed.person.objectID.persistentStore == privateStore)
            #expect(await ClassroomNames.foldMyRows(role: .leadGuide, in: context) == 0)
            #expect(context.safeSave())
        }
        #expect(!elsewhere.isDeleted)
        #expect(elsewhere.displayName == "Mr. D")
    }

    // MARK: - A name typed before the record name is known

    @Test("A name typed before the record name is known waits, then a view-context save writes it")
    func waitingNameIsWrittenOnceTheRecordNameArrives() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let viewContext = stack.viewContext
        try await Support.asDevice(recordName: nil) {
            #expect(await ClassroomNames.setMyName("Danny", role: .leadGuide, in: viewContext).written == nil)
            #expect(ClassroomIdentity.nameWaitingAs == .leadGuide)
            #expect(ClassroomNames.myName(role: .leadGuide, in: viewContext) == "Danny")
            #expect(everyone(in: viewContext).isEmpty)
            // Still no record name: nothing can be written yet.
            #expect(await !ClassroomNames.writeWaitingName(in: viewContext))

            // `refreshRecordName()` answers.
            ClassroomIdentity.currentUserRecordName = "_guide"
            var savedOn: [NSManagedObjectContext] = []
            var created: [NSManagedObject] = []
            let wrote = await ClassroomNames.writeWaitingName(now: at(30), in: viewContext) { context, new in
                savedOn.append(context)
                created += new
                return context.safeSave()
            }
            #expect(wrote)
            #expect(savedOn.count == 1)
            #expect(savedOn.first === viewContext)
            let row = try #require(everyone(in: viewContext).first)
            #expect(created.map(\.objectID) == [row.objectID])
            #expect(row.displayName == "Danny")
            #expect(row.role == .leadGuide)
            #expect(row.modifiedAt == at(30))
            #expect(!viewContext.hasChanges)

            // Written: nothing waits, and the guide's own copy on the device goes.
            #expect(ClassroomIdentity.nameWaitingAs == nil)
            #expect(ClassroomIdentity.displayName == nil)
            #expect(ClassroomNames.myName(role: .leadGuide, in: viewContext) == "Danny")
            #expect(await !ClassroomNames.writeWaitingName(in: viewContext))
        }
    }

    @Test("An assistant's waiting name, or one she gave before the list existed, joins it and stays on her phone")
    func assistantWaitingName() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        await Support.asDevice(recordName: nil) {
            await ClassroomNames.setMyName("Ana", role: .assistant, in: context)
            ClassroomIdentity.currentUserRecordName = "_ana"
            #expect(await ClassroomNames.writeWaitingName(role: .assistant, in: context))
            #expect(ClassroomIdentity.displayName == "Ana", "her marks are stamped with it")
        }
        #expect(ClassroomNames.name(forRecordName: "_ana", in: context) == "Ana")

        // Bea named herself on an older build: a name on her phone, no row.
        await Support.asDevice(recordName: "_bea", displayName: "Bea") {
            #expect(await ClassroomNames.writeWaitingName(role: .assistant, in: context))
            #expect(await !ClassroomNames.writeWaitingName(role: .assistant, in: context), "once is enough")
        }
        #expect(ClassroomNames.name(forRecordName: "_bea", in: context) == "Bea")
    }

    @Test("Nothing waiting and nothing to fold saves nothing, even with other changes pending")
    func writeWaitingNameLeavesOtherChangesAlone() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        await Support.asDevice(recordName: "_guide") {
            await ClassroomNames.setMyName("Danny", role: .leadGuide, in: context)
            #expect(context.safeSave())
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Unsaved")
            var saves = 0
            #expect(await !ClassroomNames.writeWaitingName(role: .leadGuide, in: context) { _, _ in
                saves += 1
                return true
            })
            #expect(saves == 0)
            #expect(context.hasChanges)
        }
    }

    @Test("The guide's new row is a classroom insert into his private store, as SharedStoreOrphanGuard reads a save")
    func guideRowReachesTheOrphanGuard() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        let privateStore = try #require(stores.first { $0.configurationName == CoreDataStack.privateConfiguration })
        let watch = SaveWatch()
        let token = NotificationCenter.default.addObserver(of: context, for: .didSave) { message in
            let inserts = SharedStoreOrphanGuard.classroomInserts(message.inserted, privateStore: privateStore)
            watch.classroomInserts += inserts
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let row = try await Support.asDevice(recordName: "_guide") {
            let written = try #require(await ClassroomNames.setMyName("Danny", role: .leadGuide, in: context).written)
            #expect(context.safeSave())
            return written.person
        }
        #expect(watch.classroomInserts == [row.objectID])
    }
}

/// What a `.didSave` observer saw.
private final class SaveWatch {
    var classroomInserts: [NSManagedObjectID] = []
}
