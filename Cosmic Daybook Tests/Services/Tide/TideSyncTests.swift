import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Sharing to-dos with Tide (plan "Simplify the app", Phase 10), against a
/// fake Tide and the notebook's real to-do write path on an in-memory store.
@Suite("Tide sync", .serialized)
@MainActor
struct TideSyncTests {

    // MARK: - Sending

    @Test("An open to-do goes to Tide with its line and its children's names, once")
    func sendsOpenTodo() async throws {
        let harness = try TideSyncHarness()
        harness.tide.add("Order pin maps")
        let maya = harness.student("Maya", "Smith")
        let etty = harness.student("Etty", "Klein")
        let todo = harness.todo("Check Maya and Etty's maps", students: [maya, etty])

        let result = await harness.run()

        guard case .synced(let report) = result else { Issue.record("not synced: \(result)"); return }
        #expect(report.sent == 1)
        let todoID = try #require(todo.id)
        let sent = try #require(harness.tide.action(notebookID: todoID))
        #expect(sent.text == "Check Maya and Etty's maps")
        #expect(sent.file == FakeTide.upperEl)
        #expect(sent.heading == "This week", "under the list's first heading")
        #expect(sent.note?.contains("For Maya Smith and Etty Klein.") == true)
        #expect(todo.tideLink == TideActionLink(file: FakeTide.upperEl, text: sent.text).string)
        let add = try #require(harness.tide.calls.first { $0.name == "add_action" })
        #expect(add.arguments["position"]?.intValue == 2, "last under the heading")
        #expect(add.arguments["revision"]?.stringValue != nil)

        await harness.run()
        #expect(harness.tide.callNames.filter { $0 == "add_action" }.count == 1, "sent once")
    }

    @Test("Two to-dos sent in one run each take the revision the last write returned")
    func sendsSeveralInOneRun() async throws {
        let harness = try TideSyncHarness()
        harness.tide.add("Order pin maps")
        harness.todo("Plan the field trip")
        harness.todo("Email the art teacher")

        await harness.run()

        #expect(harness.tide.action("Plan the field trip") != nil)
        #expect(harness.tide.action("Email the art teacher") != nil)
        #expect(harness.todos.allSatisfy { $0.tideLink != nil })
    }

    @Test("An automatic work check-in is never sent")
    func workCheckInsStayHere() async throws {
        let harness = try TideSyncHarness()
        let checkIn = harness.todo("Check in with Maya on fractions", workID: UUID())

        await harness.run()

        #expect(!harness.tide.callNames.contains("add_action"))
        #expect(checkIn.tideLink == nil)
        #expect(harness.tide.actions.isEmpty)
    }

    @Test("A list changed under the read stops the sending; the next run reads again and sends")
    func staleRevisionReadsAgain() async throws {
        let harness = try TideSyncHarness()
        harness.tide.add("Order pin maps")
        let todo = harness.todo("Plan the field trip")
        harness.tide.editBeforeNextAdd = true

        guard case .synced(let first) = await harness.run() else { Issue.record("not synced"); return }
        #expect(first.tryAgain)
        #expect(todo.tideLink == nil)
        #expect(harness.tide.callNames.filter { $0 == "add_action" }.count == 1, "not retried in the same run")

        await harness.run()
        #expect(todo.tideLink != nil)
        #expect(harness.tide.actions.filter { $0.text == "Plan the field trip" }.count == 1)
    }

    // MARK: - Showing Tide's

    @Test("An open action in a picked list becomes a notebook to-do, once")
    func pullsTideActions() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil,
                                    note: "Use the white tape.", due: "2026-10-21")

        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }

        #expect(report.pulled == 1)
        let todo = try #require(harness.todo(linkedTo: link))
        #expect(todo.title == "Label the shelves")
        #expect(todo.notes == "Use the white tape.")
        #expect(todo.dueDate == (try CoreDataTestHelpers.day("2026-10-21")))
        #expect(todo.tideListName == "Room Setup")
        #expect(!harness.tide.callNames.contains("add_action"), "a to-do from Tide isn't sent back")

        await harness.run()
        #expect(harness.todos.count == 1)
    }

    @Test("A list not picked to show isn't brought in")
    func unpickedListStaysInTide() async throws {
        let harness = try TideSyncHarness()
        harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        harness.settings.shownLists = [FakeTide.upperEl]

        await harness.run()

        #expect(harness.todos.isEmpty)
    }

    // MARK: - Ticks

    @Test("A tick here ticks the action off in Tide; unticking here isn't carried")
    func tickHereGoesToTide() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))

        TodoCompletionService.complete(todo)
        #expect(CoreDataTestHelpers.save(harness.context))
        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }

        #expect(report.tickedInTide == 1)
        #expect(harness.tide.action("Label the shelves")?.state == "done")
        let tick = try #require(harness.tide.calls.last { $0.name == "complete_action" })
        #expect(tick.arguments["file"]?.stringValue == FakeTide.roomSetup)
        #expect(tick.arguments["action"]?.stringValue == "Label the shelves")

        TodoCompletionService.reopen(todo)
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()
        #expect(!todo.isCompleted, "the untick stays")
        #expect(harness.tide.action("Label the shelves")?.state == "done", "and isn't carried to Tide")
        #expect(harness.tide.callNames.filter { $0 == "complete_action" }.count == 1)
    }

    @Test("A tick in Tide ticks the copy here; unticking here afterwards isn't undone")
    func tickInTideClosesCopy() async throws {
        let harness = try TideSyncHarness()
        harness.tide.add("Order pin maps")
        let todo = harness.todo("Plan the field trip")
        await harness.run()

        harness.tide.setState("done", of: "Plan the field trip")
        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }
        #expect(report.closedHere == 1)
        #expect(todo.isCompleted)

        TodoCompletionService.reopen(todo)
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()
        #expect(!todo.isCompleted)
        #expect(!harness.tide.callNames.contains("complete_action"))
    }

    @Test("An action dropped, deleted or moved out of the lists closes its copy here", arguments: [
        "dropped", "deleted", "moved"
    ])
    func goneFromTideClosesCopy(how: String) async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))

        switch how {
        case "dropped": harness.tide.setState("dropped", of: "Label the shelves")
        case "deleted": harness.tide.actions.removeAll { $0.text == "Label the shelves" }
        default: harness.tide.move("Label the shelves", to: FakeTide.home)
        }
        await harness.run()

        #expect(todo.isCompleted)
        #expect(!harness.tide.callNames.contains("complete_action"), "nothing is ticked back")
    }

    @Test("An action waiting or parked someday in Tide keeps its copy open")
    func waitingIsNotGone() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        await harness.run()
        harness.tide.setState("waiting", of: "Label the shelves")

        await harness.run()

        #expect(harness.todo(linkedTo: link)?.isCompleted == false)
    }

    @Test("A Tide repeat ticked here moves on in Tide, and its copy stays open with the new date")
    func tickedRepeatRolls() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Water the plants", in: FakeTide.roomSetup, heading: nil,
                                    due: "2026-10-19", repeats: true)
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))

        TodoCompletionService.complete(todo)
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()

        #expect(!todo.isCompleted)
        #expect(todo.dueDate == (try CoreDataTestHelpers.day("2026-10-26")))
    }

    // MARK: - Wording and recovery

    @Test("Reworded in Tide: found again by its notebook line, with Tide's new words")
    func rewordedInTideIsFoundAgain() async throws {
        let harness = try TideSyncHarness()
        harness.tide.add("Order pin maps")
        let todo = harness.todo("Plan the field trip")
        await harness.run()

        harness.tide.reword("Plan the field trip", to: "Plan the October field trip")
        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }

        #expect(report.relinked == 1)
        #expect(!todo.isCompleted)
        #expect(todo.title == "Plan the October field trip")
        #expect(todo.tideLink == TideActionLink(file: FakeTide.upperEl, text: "Plan the October field trip").string)
        #expect(harness.todos.filter { $0.title.contains("field trip") }.count == 1, "no second copy")
    }

    @Test("Sent but never linked (a crash mid-send): the action carrying its line is taken, not sent again")
    func crashMidSendIsRecovered() async throws {
        let harness = try TideSyncHarness()
        let todo = harness.todo("Plan the field trip")
        let id = try #require(todo.id)
        harness.tide.add("Plan the field trip", note: TideNotebookMarker.line(for: id))

        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }

        #expect(report.relinked == 1)
        #expect(!harness.tide.callNames.contains("add_action"))
        #expect(!todo.isCompleted, "taken back, not judged gone")
        #expect(todo.tideLink == TideActionLink(file: FakeTide.upperEl, text: "Plan the field trip").string)
        #expect(harness.tide.actions.count == 1)
        #expect(harness.todos.count == 1)
    }

    @Test("A notebook title edit after sending stays in the notebook")
    func titleEditDoesntTravel() async throws {
        let harness = try TideSyncHarness()
        let todo = harness.todo("Plan the field trip")
        await harness.run()

        todo.title = "Plan the trip to the museum"
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()

        #expect(harness.tide.action("Plan the field trip") != nil)
        #expect(harness.tide.action("Plan the trip to the museum") == nil)
        #expect(!todo.isCompleted)
    }
}
