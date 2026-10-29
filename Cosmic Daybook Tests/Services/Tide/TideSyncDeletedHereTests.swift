import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-29, part 2 #9: a to-do shown from a Tide action whose
/// note couldn't take the notebook line came back on the next run after it
/// was deleted here, as its action looked like one made in Tide. The action's
/// address is kept now (`TideSyncState.unmarkedLinks`) until it's marked or
/// gone from Tide's lists.
@Suite("Tide sync: a to-do deleted here stays deleted", .serialized)
@MainActor
struct TideSyncDeletedHereTests {

    @Test("Deleted before its action took the notebook line: not shown again, and its twin stays")
    func deletedUnmarkedStaysDeleted() async throws {
        let harness = try TideSyncHarness()
        // The same words twice: Tide can't tell which note to put a line in.
        harness.tide.add("Order more paper", in: FakeTide.roomSetup, heading: nil)
        harness.tide.add("Order more paper", in: FakeTide.roomSetup, heading: nil)
        await harness.run()
        #expect(harness.todos.count == 2)
        #expect(harness.tide.actions.allSatisfy { $0.note == nil }, "neither could be marked")
        #expect(harness.saved.unmarkedLinks.count == 2)

        harness.context.delete(try #require(harness.todos.first))
        #expect(CoreDataTestHelpers.save(harness.context))

        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }
        #expect(report.pulled == 0, "the deleted one isn't shown again")
        #expect(harness.todos.count == 1, "its twin stays")
        await harness.run()
        #expect(harness.todos.count == 1, "nor on the run after")
        #expect(harness.saved.unmarkedLinks.count == 2, "kept while the actions are in Tide")

        // Both done in Tide: the twin closes here, and nothing is left to keep back.
        for index in harness.tide.actions.indices { harness.tide.actions[index].state = "done" }
        await harness.run()
        #expect(harness.todos.first?.isCompleted == true)
        #expect(harness.saved.unmarkedLinks.isEmpty)
    }

    @Test("An action marked at once keeps nothing back: its line does that")
    func markedActionKeepsNothing() async throws {
        let harness = try TideSyncHarness()
        harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        await harness.run()
        let todo = try #require(harness.todos.first)
        #expect(harness.tide.action(notebookID: try #require(todo.id)) != nil)
        #expect(harness.saved.unmarkedLinks.isEmpty)

        harness.context.delete(todo)
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()
        #expect(harness.todos.isEmpty, "the line keeps it from coming back")
    }
}
