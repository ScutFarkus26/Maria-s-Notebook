import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The name list's writes wait for CloudKit's answer about zones off the main
/// thread (2026-10-06 freeze fix), so things can change during the wait: the
/// account, the rows, a second trigger or a second save. The lookup is
/// `ClassroomNames.zoneLookupOverride`, and `zoneLookupHook` acts inside the
/// wait.
@Suite("Classroom names: waiting for the zones", .serialized)
@MainActor
struct ClassroomNamesWaitTests {

    private typealias Support = ClassroomNamesTestSupport

    /// What happened during a test, kept where the hook and tasks can reach it.
    private final class Log {
        var lookups = 0
        var saves: [String] = []
        var writes: [Task<Bool, Never>] = []
        var newerName: Task<ClassroomNames.NameSet, Never>?
    }

    private func at(_ seconds: TimeInterval) -> Date {
        Support.at(seconds)
    }

    private func everyone(in context: NSManagedObjectContext) -> [CDClassroomPerson] {
        context.safeFetch(CDFetchRequest(CDClassroomPerson.self))
    }

    /// Runs `body` with every row's zone looked up as "not sent", and with
    /// `during` run inside the first lookup's wait. Counts the lookups in `log`.
    private func whileLookingUp<T>(
        _ log: Log,
        during: @escaping () async -> Void,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let lookup: @Sendable ([NSManagedObjectID]) -> [NSManagedObjectID: String] = { _ in [:] }
        let hook = ClassroomNames.LookupHook {
            log.lookups += 1
            guard log.lookups == 1 else { return }
            await during()
            // Lets any task started above reach its own wait first.
            for _ in 0..<5 { await Task.yield() }
        }
        return try await ClassroomNames.$zoneLookupOverride.withValue(lookup) {
            try await ClassroomNames.$zoneLookupHook.withValue(hook) {
                try await body()
            }
        }
    }

    @Test("Another account signing in during the wait gets nothing written under the last one's name")
    func accountChangeDuringTheWait() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let log = Log()
        let wrote = await whileLookingUp(log, during: { ClassroomIdentity.currentUserRecordName = "_bea" }, {
            await Support.asDevice(recordName: "_ana", displayName: "Ana") {
                ClassroomNames.markWaiting(as: .assistant)
                return await ClassroomNames.writeWaitingName(role: .assistant, in: context) { context, _ in
                    log.saves.append("write")
                    return context.safeSave()
                }
            }
        })
        #expect(!wrote)
        #expect(log.saves.isEmpty)
        #expect(!context.hasChanges)
        #expect(everyone(in: context).isEmpty, "no row under _ana's record name")
    }

    @Test("A row deleted during the wait is neither folded nor read")
    func rowDeletedDuringTheWait() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let oldest = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), in: context)
        Support.person("_guide", "Dan", role: .leadGuide, created: at(10), modified: at(20), in: context)
        let gone = Support.person("_guide", "Daniel", role: .leadGuide, created: at(20), modified: at(90), in: context)
        #expect(context.safeSave())
        let log = Log()

        let folded = await whileLookingUp(log, during: { context.delete(gone) }, {
            await Support.asDevice(recordName: "_guide") {
                await ClassroomNames.foldMyRows(role: .leadGuide, in: context)
            }
        })
        #expect(folded == 1, "only the copy still there")
        #expect(oldest.displayName == "Dan", "the newest name among the rows still there")
        #expect(context.safeSave())
        #expect(everyone(in: context).map(\.objectID) == [oldest.objectID])
    }

    @Test("A copy that arrives during the wait is kept for the next run")
    func copyWithNoAnswerIsKept() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let oldest = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), in: context)
        Support.person("_guide", "Dan", role: .leadGuide, created: at(10), in: context)
        #expect(context.safeSave())
        let log = Log()
        var late: CDClassroomPerson?

        let folded = await whileLookingUp(log, during: {
            late = Support.person("_guide", "Daniel", role: .leadGuide, created: at(20), in: context)
            #expect(context.safeSave())
        }, {
            await Support.asDevice(recordName: "_guide") {
                await ClassroomNames.foldMyRows(role: .leadGuide, in: context)
            }
        })
        #expect(folded == 1)
        #expect(context.safeSave())
        let kept = try #require(late)
        #expect(Set(everyone(in: context).map(\.objectID)) == [oldest.objectID, kept.objectID])
    }

    @Test("Writes asked for during a run give exactly one more run, with the latest call's save")
    func triggersDuringARunGiveOneMoreRun() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let oldest = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(30), in: context)
        #expect(context.safeSave())
        let log = Log()

        let first = await whileLookingUp(log, during: {
            // An older copy of the name arrives (nothing to carry over), then
            // two more triggers (an import, a return to the app).
            Support.person("_guide", "Danny", role: .leadGuide, created: at(10), modified: at(20), in: context)
            #expect(context.safeSave())
            for label in ["second", "third"] {
                log.writes.append(Task {
                    await ClassroomNames.writeWaitingName(role: .leadGuide, in: context) { context, _ in
                        log.saves.append(label)
                        return context.safeSave()
                    }
                })
            }
        }, {
            await Support.asDevice(recordName: "_guide") {
                await ClassroomNames.writeWaitingName(role: .leadGuide, in: context) { context, _ in
                    log.saves.append("first")
                    return context.safeSave()
                }
            }
        })
        var later: [Bool] = []
        for write in log.writes { later.append(await write.value) }

        #expect(!first, "the copy arrived during its wait, so it kept it")
        #expect(log.lookups == 2, "one more run, not one per trigger")
        #expect(log.saves == ["third"], "the rerun saves with the latest call's closure")
        #expect(later == [true, true], "both later callers get the rerun's answer")
        #expect(everyone(in: context).map(\.objectID) == [oldest.objectID])
    }

    @Test("A name overtaken by a newer one during the wait writes nothing")
    func overtakenNameWritesNothing() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let log = Log()

        let older = await whileLookingUp(log, during: {
            log.newerName = Task { await ClassroomNames.setMyName("Anna", role: .leadGuide, in: context) }
        }, {
            await Support.asDevice(recordName: "_guide") {
                let older = await ClassroomNames.setMyName("Ann", role: .leadGuide, in: context)
                _ = await log.newerName?.value
                return older
            }
        })
        let newer = try #require(await log.newerName?.value)
        if case .overtaken = older {} else { Issue.record("the older name was written: \(older)") }
        #expect(newer.written?.person.displayName == "Anna")
        #expect(context.safeSave())
        #expect(everyone(in: context).map(\.displayName) == ["Anna"])
    }
}

// MARK: - Review fixes (2026-10-06)

extension ClassroomNamesWaitTests {

    private var classroom: String { "com.apple.coredata.cloudkit.share.NOW" }

    private func pin(_ role: CDClassroomMembership.ClassroomRole, in context: NSManagedObjectContext) {
        let membership = CDClassroomMembership(context: context)
        membership.role = role
        membership.classroomZoneID = classroom
    }

    @Test("Another account signing in during a rename takes the name back: nothing waits for the new account")
    func accountChangeDuringARename() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let log = Log()
        let (set, waiting, name) = await whileLookingUp(log, during: {
            ClassroomIdentity.currentUserRecordName = "_bea"
        }, {
            await Support.asDevice(recordName: "_ana", displayName: "Ana") {
                let set = await ClassroomNames.setMyName("Annie", role: .assistant, in: context)
                return (set, ClassroomIdentity.nameWaitingAs, ClassroomIdentity.displayName)
            }
        })
        if case .nothing = set {} else { Issue.record("expected nothing written, got \(set)") }
        #expect(waiting == nil, "nothing waits to go in under _bea")
        #expect(name == "Ana", "the name from before the rename")
        #expect(everyone(in: context).isEmpty)
    }

    @Test("A rename waits on the device from the moment it's typed, so a quit during the wait doesn't lose it")
    func renameWaitsDuringTheLookup() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let log = Log()
        var during: (String?, CDClassroomMembership.ClassroomRole?)?
        let (set, waiting, name) = await whileLookingUp(log, during: {
            during = (ClassroomIdentity.displayName, ClassroomIdentity.nameWaitingAs)
        }, {
            await Support.asDevice(recordName: "_guide") {
                let set = await ClassroomNames.setMyName("Danny", role: .leadGuide, in: context)
                return (set, ClassroomIdentity.nameWaitingAs, ClassroomIdentity.displayName)
            }
        })
        #expect(during?.0 == "Danny")
        #expect(during?.1 == .leadGuide)
        #expect(set.written?.person.displayName == "Danny")
        #expect(waiting == nil, "written: nothing waits")
        #expect(name == nil, "the guide's own copy goes once his row has it")

        // The stores going during the wait (her stack rebuilt): it keeps waiting.
        let coordinator = try #require(context.persistentStoreCoordinator)
        let stores = coordinator.persistentStores
        let kept = await whileLookingUp(Log(), during: {
            for store in stores { try? coordinator.remove(store) }
        }, {
            await Support.asDevice(recordName: "_guide") {
                let set = await ClassroomNames.setMyName("Daniel", role: .leadGuide, in: context)
                return (set, ClassroomIdentity.displayName, ClassroomIdentity.nameWaitingAs)
            }
        })
        if case .waiting = kept.0 {} else { Issue.record("expected the name to wait, got \(kept.0)") }
        #expect(kept.1 == "Daniel")
        #expect(kept.2 == .leadGuide)
    }

    @Test("A guide's name waiting on a notebook that joined a class as an assistant asks the zones of his own rows")
    func waitingRoleRowsAreLookedUp() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        let privateStore = try #require(stores.first { $0.configurationName == CoreDataStack.privateConfiguration })
        pin(.assistant, in: context)
        let mine = Support.person(
            "_guide", "Dan", role: .leadGuide, created: at(0), store: privateStore, in: context
        )
        #expect(context.safeSave())
        let asked = Asked()
        let zones = [mine.objectID: "com.apple.coredata.cloudkit.share.MINE"]
        let lookup: @Sendable ([NSManagedObjectID]) -> [NSManagedObjectID: String] = { ids in
            asked.add(ids)
            return zones.filter { ids.contains($0.key) }
        }
        await ClassroomNames.$zoneLookupOverride.withValue(lookup) {
            await Support.asDevice(recordName: "_guide", displayName: "Danny") {
                ClassroomNames.markWaiting(as: .leadGuide)
                _ = await ClassroomNames.writeWaitingName(in: context)
            }
        }
        #expect(asked.ids.contains(mine.objectID), "his row's zone was asked, not the assistant store's")
        #expect(mine.displayName == "Dan", "a row in another classroom's zone is left alone")
    }

    @Test("A copy from a previous classroom arriving during a rename is neither renamed nor kept as the row")
    func unansweredCopyIsLeftOutOfTheWrite() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        pin(.assistant, in: context)
        let now = Support.person("_ana", "Ana", role: .assistant, created: at(100), in: context)
        #expect(context.safeSave())
        let zones = [now.objectID: classroom]
        let lookup: @Sendable ([NSManagedObjectID]) -> [NSManagedObjectID: String] = { ids in
            zones.filter { ids.contains($0.key) }
        }
        var before: CDClassroomPerson?
        let hook = ClassroomNames.LookupHook {
            before = Support.person("_ana", "Ana B.", role: .assistant, created: at(0), in: context)
            #expect(context.safeSave())
        }
        let set = await ClassroomNames.$zoneLookupOverride.withValue(lookup) {
            await ClassroomNames.$zoneLookupHook.withValue(hook) {
                await Support.asDevice(recordName: "_ana", displayName: "Annie") {
                    await ClassroomNames.setMyName("Annie", role: .assistant, in: context)
                }
            }
        }
        let late = try #require(before)
        #expect(set.written?.person.objectID == now.objectID)
        #expect(now.displayName == "Annie")
        #expect(late.displayName == "Ana B.")
        #expect(context.safeSave())
        #expect(everyone(in: context).count == 2, "the late copy waits for the next run's answer")
    }

    @Test("Stores gone during the wait (her stack rebuilt): nothing is written, and the name keeps waiting")
    func storesGoneDuringTheWait() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let coordinator = try #require(context.persistentStoreCoordinator)
        let log = Log()
        let (wrote, waiting) = await whileLookingUp(log, during: {
            for store in coordinator.persistentStores { try? coordinator.remove(store) }
        }, {
            await Support.asDevice(recordName: "_guide", displayName: "Danny") {
                ClassroomNames.markWaiting(as: .leadGuide)
                let wrote = await ClassroomNames.writeWaitingName(role: .leadGuide, in: context) { context, _ in
                    log.saves.append("write")
                    return context.safeSave()
                }
                return (wrote, ClassroomIdentity.nameWaitingAs)
            }
        })
        #expect(!wrote)
        #expect(log.saves.isEmpty)
        #expect(!context.hasChanges, "no row made in a context with no stores")
        #expect(waiting == .leadGuide)
    }

    /// The IDs a lookup was asked about.
    nonisolated private final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: Set<NSManagedObjectID> = []

        var ids: Set<NSManagedObjectID> { lock.withLock { asked } }

        func add(_ ids: [NSManagedObjectID]) {
            lock.withLock { asked.formUnion(ids) }
        }
    }
}
