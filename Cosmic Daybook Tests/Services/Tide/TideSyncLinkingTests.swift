import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The review's fixes to how the sharing keeps a to-do tied to its action:
/// the same words twice, the notebook line on Tide's own actions, a move to
/// a list the sharing doesn't show, and ticks that can't be aimed.
@Suite("Tide sync: same words, lines and moves", .serialized)
@MainActor
struct TideSyncLinkingTests {

    @Test("Two open to-dos with the same words keep an action each, run after run")
    func sameWordsStayApart() async throws {
        let harness = try TideSyncHarness()
        let first = harness.todo("Water the plants")
        let second = harness.todo("Water the plants")
        await harness.run()
        let firstID = try #require(first.id)
        let secondID = try #require(second.id)
        #expect(harness.tide.action(notebookID: firstID) != nil)
        #expect(harness.tide.action(notebookID: secondID) != nil)

        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }

        #expect(report.relinked == 0)
        #expect(report.closedHere == 0)
        #expect(!first.isCompleted && !second.isCompleted)
        #expect(harness.tide.actions.count == 2)
        #expect(harness.todos.count == 2, "neither action comes back as a third to-do")
    }

    @Test("A tick Tide can't aim (the same words twice) is said plainly and asked again, never given up")
    func ambiguousTickIsRetried() async throws {
        let harness = try TideSyncHarness()
        let lastWeek = harness.todo("Water the plants")
        await harness.run()
        TodoCompletionService.complete(lastWeek)
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()
        #expect(harness.tide.actions.first?.state == "done")
        let thisWeek = harness.todo("Water the plants")
        await harness.run()
        TodoCompletionService.complete(thisWeek)
        #expect(CoreDataTestHelpers.save(harness.context))

        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }
        #expect(report.notTicked == ["Water the plants"])
        #expect(TideSyncMessages.notTicked(report.notTicked).contains("Tick it off in Tide"))
        let ticksBefore = harness.tide.callNames.filter { $0 == "complete_action" }.count
        await harness.run()
        #expect(harness.tide.callNames.filter { $0 == "complete_action" }.count == ticksBefore + 1, "asked again")

        // Danny ticks it off in Tide: the notebook stops asking.
        let open = try #require(harness.tide.actions.firstIndex { $0.state == "open" })
        harness.tide.actions[open].state = "done"
        guard case .synced(let after) = await harness.run() else { Issue.record("not synced"); return }
        #expect(after.notTicked.isEmpty)
        #expect(harness.tide.callNames.filter { $0 == "complete_action" }.count == ticksBefore + 1)
    }

    @Test("Made in Tide: the notebook line goes after Danny's own words, so a reword keeps the link")
    func tideActionsGetTheLine() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil,
                                    note: "Me: ask the office for tape first.")
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))
        let id = try #require(todo.id)
        #expect(harness.tide.action("Label the shelves")?.note
            == "Me: ask the office for tape first.\n\n" + TideNotebookMarker.line(for: id))
        let maya = harness.student("Maya", "Smith")
        todo.resolvedStudentIDs = [try #require(maya.id)]
        todo.notes = "Use the white tape."
        #expect(CoreDataTestHelpers.save(harness.context))

        harness.tide.reword("Label the shelves", to: "Label the shelves and bins")
        await harness.run()

        #expect(!todo.isCompleted, "not closed")
        #expect(todo.title == "Label the shelves and bins")
        #expect(todo.resolvedStudentIDs == [maya.id], "what was added here stays")
        #expect(todo.notes == "Use the white tape.")
        #expect(harness.todos.count == 1, "no fresh copy")
    }

    @Test("A first-run match gets its notebook line too")
    func firstRunMatchGetsTheLine() async throws {
        let harness = try TideSyncHarness(confirmed: false)
        harness.tide.add("Order pin maps", in: FakeTide.roomSetup, heading: nil)
        let todo = harness.todo("Order more pin maps")
        guard case .needsFirstRunOK(let proposal) = await harness.run() else { Issue.record("no proposal"); return }

        _ = await harness.engine.confirmFirstRun(proposal.matches, settings: harness.settings, now: harness.now)

        let id = try #require(todo.id)
        #expect(harness.tide.action("Order pin maps")?.note == TideNotebookMarker.line(for: id))
        #expect(todo.title == "Order more pin maps", "a match keeps the notebook's own words")
    }

    @Test("Moved in Tide to a list the notebook doesn't show: left open here, with its new address")
    func movedToUnpickedList() async throws {
        let harness = try TideSyncHarness()
        harness.settings.shownLists = [FakeTide.upperEl]
        let todo = harness.todo("Plan the field trip")
        await harness.run()

        harness.tide.move("Plan the field trip", to: FakeTide.roomSetup)
        await harness.run()

        #expect(!todo.isCompleted)
        #expect(todo.tideLink == TideActionLink(file: FakeTide.roomSetup, text: "Plan the field trip").string)
    }

    @Test("Of two copies of one to-do, the linked one is used, and dedup keeps the link")
    func duplicatesKeepTheLink() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let id = UUID()
        let unlinked = CDTodoItem(context: context)
        unlinked.id = id
        unlinked.title = "Label the shelves"
        unlinked.createdAt = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let linked = CDTodoItem(context: context)
        linked.id = id
        linked.title = "Label the shelves"
        linked.createdAt = Date(timeIntervalSinceReferenceDate: 780_000_600)
        linked.tideLink = TideActionLink(file: FakeTide.roomSetup, text: "Label the shelves").string
        #expect(CoreDataTestHelpers.save(context))
        let expected = try #require(linked.tideLink)

        let store = NotebookTideTodoStore(context: context, saveCoordinator: SaveCoordinator())
        #expect(store.todos(alsoClosed: []).map(\.tideLink) == [expected])

        let results = DataCleanupService.deduplicateAllModels(
            using: context, scope: DeduplicationScope(insertedEntities: ["TodoItem"])
        )
        #expect(results["TodoItem"] == 1)
        let left = context.safeFetch(CDFetchRequest(CDTodoItem.self))
        #expect(left.count == 1)
        #expect(left.first?.tideLink == expected)
    }
}
