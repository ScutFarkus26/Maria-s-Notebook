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
