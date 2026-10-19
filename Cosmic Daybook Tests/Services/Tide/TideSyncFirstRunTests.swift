import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Tide sharing's first run, its problems, and the call it never makes.
@Suite("Tide sync: first run and problems", .serialized)
@MainActor
struct TideSyncFirstRunTests {

    // MARK: - First run

    @Test("The first run proposes matches and writes nothing until Danny confirms")
    func firstRunWaitsForOK() async throws {
        let harness = try TideSyncHarness(confirmed: false)
        let link = harness.tide.add("Order pin maps", in: FakeTide.roomSetup, heading: nil)
        harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        let matchID: UUID = try #require(harness.todo("Order more pin maps").id)
        harness.todo("Plan the field trip")

        let result = await harness.run()

        guard case .needsFirstRunOK(let proposal) = result else { Issue.record("no proposal: \(result)"); return }
        let proposed: [UUID] = proposal.matches.map(\.notebookID)
        #expect(proposed == [matchID])
        #expect(proposal.matches.first?.tideLink == link.string)
        #expect(proposal.toSend == 1)
        #expect(proposal.toShow == 1)
        #expect(harness.tide.callNames == ["get_area"], "read only")
        #expect(harness.todos.count == 2, "nothing brought in")
        #expect(harness.todos.allSatisfy { $0.tideLink == nil }, "nothing linked")
        #expect(!harness.context.hasChanges)
    }

    @Test("Once confirmed, the matches are linked, the rest go across, and nothing is doubled")
    func confirmedFirstRunLinksAndSends() async throws {
        let harness = try TideSyncHarness(confirmed: false)
        let link = harness.tide.add("Order pin maps", in: FakeTide.roomSetup, heading: nil)
        harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        let match = harness.todo("Order more pin maps")
        let other = harness.todo("Plan the field trip")
        let matchID: UUID = try #require(match.id)
        guard case .needsFirstRunOK(let proposal) = await harness.run() else { Issue.record("no proposal"); return }

        let confirmed = await harness.engine.confirmFirstRun(
            proposal.matches, settings: harness.settings, now: harness.now
        )

        guard case .synced = confirmed else { Issue.record("not synced: \(confirmed)"); return }
        #expect(match.tideLink == link.string)
        #expect(!match.isCompleted, "a match stays open")
        let pinActions = harness.tide.actions.filter { $0.text.contains("pin maps") }
        #expect(pinActions.count == 1, "the match isn't sent")
        #expect(other.tideLink != nil, "the rest are sent")
        #expect(harness.todos.count == 3, "and Tide's own to-do comes in")
        #expect(harness.saved.firstRunLinked == [matchID.uuidString])
        #expect(harness.saved.firstRunConfirmedAt != nil)
    }

    @Test("A match Danny unticks is two to-dos: each goes to the other side")
    func uncheckedMatchIsTwoTodos() async throws {
        let harness = try TideSyncHarness(confirmed: false)
        harness.tide.add("Order pin maps", in: FakeTide.roomSetup, heading: nil)
        let todo = harness.todo("Order more pin maps")
        guard case .needsFirstRunOK = await harness.run() else { Issue.record("no proposal"); return }

        _ = await harness.engine.confirmFirstRun([], settings: harness.settings, now: harness.now)

        #expect(todo.tideLink?.contains("Upper%20Elementary") == true)
        #expect(harness.todos.count == 2)
    }

    // MARK: - Problems

    @Test("A changed token: a plain status, and nothing written on either side")
    func changedTokenWritesNothing() async throws {
        let harness = try TideSyncHarness()
        let todo = harness.todo("Plan the field trip")
        harness.tide.failure = .tokenRefused

        let result = await harness.run()

        #expect(result == .stopped(.tokenRefused))
        #expect(TideSyncProblem.tokenRefused.message == TideSyncMessages.tokenRefused)
        #expect(TideSyncMessages.tokenRefused.contains("Settings › Claude"))
        #expect(todo.tideLink == nil)
        #expect(!harness.context.hasChanges)
        #expect(harness.tide.callNames == ["get_area"])
    }

    @Test("Tide closed: says so plainly, and nothing changes")
    func tideClosed() async throws {
        let harness = try TideSyncHarness()
        harness.todo("Plan the field trip")
        harness.tide.failure = .notRunning

        let result = await harness.run()

        #expect(result == .stopped(.tideNotRunning))
        #expect(
            TideSyncProblem.tideNotRunning.message == "Tide isn't open on this Mac. To-dos will go across when it is."
        )
        #expect(!harness.context.hasChanges)
    }

    @Test("A to-do Tide refuses is named, and not sent again until its title changes")
    func refusedSendIsNotRepeated() async throws {
        let harness = try TideSyncHarness()
        let todo = harness.todo("Plan the field trip")
        harness.tide.refusedTitles = ["Plan the field trip"]

        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }
        #expect(report.notSent == ["Plan the field trip"])
        #expect(!TideSyncMessages.notSent(report.notSent).contains("due"), "Tide's own words stay in Details")
        await harness.run()
        #expect(harness.tide.callNames.filter { $0 == "add_action" }.count == 1)

        todo.title = "Plan the October field trip"
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()
        #expect(todo.tideLink != nil)
    }

    @Test("The sync never asks Tide what changed: that would move Danny's Claude cursor")
    func neverCallsChangesSince() async throws {
        let harness = try TideSyncHarness(confirmed: false)
        harness.tide.add("Order pin maps", in: FakeTide.roomSetup, heading: nil)
        let todo = harness.todo("Plan the field trip")
        guard case .needsFirstRunOK(let proposal) = await harness.run() else { Issue.record("no proposal"); return }
        _ = await harness.engine.confirmFirstRun(proposal.matches, settings: harness.settings, now: harness.now)
        TodoCompletionService.complete(todo)
        #expect(CoreDataTestHelpers.save(harness.context))
        harness.tide.setState("done", of: "Order pin maps")
        await harness.run()

        let used = Set(harness.tide.callNames)
        #expect(!used.contains("changes_since"))
        #expect(used.isSubset(of: ["get_area", "add_action", "complete_action", "update_action", "list_actions"]))
    }
}
