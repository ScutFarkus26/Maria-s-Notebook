import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-11-02, the Tide to-dos: edits here to a to-do made in Tide
/// go to Tide (#3), a tick outlives its to-do (#11), a repeat ticked on both
/// sides rolls once (#46), shown to-dos are saved before Tide's notes name
/// them (#47), a later start plans the to-do (#48), and a to-do known by
/// address only follows a reword or a move (#51).
@Suite("Tide sync: edits, ticks and starts", .serialized)
@MainActor
struct TideSyncEditsAndTicksTests {

    // MARK: - #3 Edits here to a to-do made in Tide

    @Test("A new title and due date here on a to-do made in Tide go to Tide, and stay")
    func editsHereGoToTide() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil, due: "2026-10-21")
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))

        todo.title = "Label the shelves and bins"
        todo.dueDate = try CoreDataTestHelpers.day("2026-10-24")
        #expect(CoreDataTestHelpers.save(harness.context))
        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }

        #expect(report.edited == 1)
        #expect(harness.tide.action("Label the shelves") == nil)
        #expect(harness.tide.action("Label the shelves and bins")?.due == "2026-10-24")
        #expect(todo.title == "Label the shelves and bins", "not put back")
        #expect(todo.dueDate == (try CoreDataTestHelpers.day("2026-10-24")))
        #expect(todo.tideLink == TideActionLink(file: FakeTide.roomSetup, text: "Label the shelves and bins").string)

        let writes = harness.tide.calls.filter { $0.name == "update_action" }.count
        await harness.run()
        #expect(harness.tide.calls.filter { $0.name == "update_action" }.count == writes, "sent once")
        #expect(todo.title == "Label the shelves and bins")
        #expect(!todo.isCompleted)
        #expect(harness.todos.count == 1, "no second copy")
    }

    @Test("A due date cleared here clears it in Tide")
    func dueClearedHere() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil, due: "2026-10-21")
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))

        todo.dueDate = nil
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()

        #expect(harness.tide.action("Label the shelves")?.due == nil)
        #expect(todo.dueDate == nil)
        let update = try #require(harness.tide.calls.last { $0.name == "update_action" })
        #expect(update.arguments["due"]?.stringValue == "")
        #expect(update.arguments["text"] == nil, "the words weren't touched")
    }

    @Test("A reword and a new date in Tide still come here, and win over a date set here since")
    func tideChangesStillCome() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil, due: "2026-10-21")
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))

        harness.tide.reword("Label the shelves", to: "Label all the shelves")
        let index = try #require(harness.tide.actions.firstIndex { $0.text == "Label all the shelves" })
        harness.tide.actions[index].due = "2026-10-28"
        todo.dueDate = try CoreDataTestHelpers.day("2026-10-23")
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()

        #expect(todo.title == "Label all the shelves")
        #expect(todo.dueDate == (try CoreDataTestHelpers.day("2026-10-28")))
        #expect(harness.tide.action("Label all the shelves")?.due == "2026-10-28")
        #expect(!harness.tide.calls.contains { $0.name == "update_action" && $0.arguments["due"] != nil })
    }

    @Test("A due date set here that has already passed stays here, is said once, and isn't sent")
    func pastDueStaysHere() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil, due: "2026-10-21")
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))
        let past = try CoreDataTestHelpers.day("2026-10-12")

        todo.dueDate = past
        #expect(CoreDataTestHelpers.save(harness.context))
        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }

        #expect(report.pastDue == ["Label the shelves"])
        #expect(TideSyncMessages.pastDue(report.pastDue).contains("still ahead"))
        #expect(todo.dueDate == past, "kept here")
        #expect(harness.tide.action("Label the shelves")?.due == "2026-10-21")
        #expect(!harness.tide.calls.contains { $0.arguments["due"] != nil }, "Tide isn't asked")

        guard case .synced(let next) = await harness.run() else { Issue.record("not synced"); return }
        #expect(next.pastDue.isEmpty, "said once")
        #expect(todo.dueDate == past)
    }

    @Test("An edit Tide won't take is said once and not sent again until it changes here")
    func refusedEditIsHeld() async throws {
        let harness = try TideSyncHarness()
        // The same words twice: Tide can't tell which one an edit names.
        harness.tide.add("Water the plants", in: FakeTide.roomSetup, heading: nil)
        harness.tide.add("Water the plants", in: FakeTide.roomSetup, heading: nil)
        await harness.run()
        let todo = try #require(harness.todos.first)

        todo.title = "Water the window plants"
        #expect(CoreDataTestHelpers.save(harness.context))
        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }
        #expect(report.notCarried == ["Water the window plants"])
        #expect(TideSyncMessages.notCarried(report.notCarried).contains("changed here but not in Tide"))
        let tries = harness.tide.calls.filter { $0.arguments["text"] != nil }.count
        #expect(tries == 1)

        guard case .synced(let next) = await harness.run() else { Issue.record("not synced"); return }
        #expect(next.notCarried.isEmpty)
        #expect(harness.tide.calls.filter { $0.arguments["text"] != nil }.count == tries, "not every run")
        #expect(todo.title == "Water the window plants", "kept here")
    }

    // MARK: - #11 A tick outlives its to-do

    @Test("Ticked here while Tide was closed, then cleared: the tick still reaches Tide")
    func tickThenClearStillGoes() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Order bead chains", in: FakeTide.roomSetup, heading: nil)
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))

        TodoCompletionService.complete(todo)
        #expect(CoreDataTestHelpers.save(harness.context))
        harness.tide.failure = .notRunning
        guard case .stopped = await harness.run() else { Issue.record("Tide should be closed"); return }
        harness.context.delete(todo)
        #expect(CoreDataTestHelpers.save(harness.context))

        harness.tide.failure = nil
        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }
        #expect(report.tickedInTide == 1)
        #expect(harness.tide.action("Order bead chains")?.state == "done")
        #expect(harness.saved.pendingTicks.isEmpty, "forgotten once it went")
        #expect(harness.todos.isEmpty, "and nothing comes back here")
    }

    @Test("Deleted while still open: nothing is ticked in Tide")
    func plainDeleteTicksNothing() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Order bead chains", in: FakeTide.roomSetup, heading: nil)
        await harness.run()
        harness.context.delete(try #require(harness.todo(linkedTo: link)))
        #expect(CoreDataTestHelpers.save(harness.context))

        await harness.run()

        #expect(harness.tide.action("Order bead chains")?.state == "open")
        #expect(!harness.tide.callNames.contains("complete_action"))
    }

    // MARK: - #46 A repeat ticked on both sides

    @Test("A repeat ticked here and in Tide before the Mac ran moves on once, not twice")
    func repeatTickedOnBothSides() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Water the plants", in: FakeTide.roomSetup, heading: nil,
                                    due: "2026-10-19", repeats: true)
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))

        TodoCompletionService.complete(todo)
        #expect(CoreDataTestHelpers.save(harness.context))
        // Danny ticks it in Tide too, which rolls it a week on.
        let index = try #require(harness.tide.actions.firstIndex { $0.text == "Water the plants" })
        harness.tide.actions[index].due = "2026-10-26"
        await harness.run()

        #expect(!harness.tide.callNames.contains("complete_action"), "not ticked a second time")
        #expect(harness.tide.action("Water the plants")?.due == "2026-10-26")
        #expect(!todo.isCompleted, "the copy moves on with it")
        #expect(todo.dueDate == (try CoreDataTestHelpers.day("2026-10-26")))
    }

    // MARK: - #47 Saved before Tide's notes name them

    @Test("To-dos from Tide are saved, and remembered, before any Tide note is marked")
    func savedBeforeMarking() async throws {
        let harness = try TideSyncHarness()
        harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        let gate = TideTestGate()
        harness.tide.gate = gate
        harness.tide.holdTool = "update_action"

        let running = Task { await harness.run() }
        #expect(await Self.eventually { gate.arrivals == 1 }, "held while marking the note")
        #expect(!harness.context.hasChanges, "saved before the note names it")
        let id = try #require(harness.todos.first?.id).uuidString
        #expect(harness.saved.fromTide.contains(id))
        #expect(harness.saved.agreedOpen[id] == true)

        gate.open()
        _ = await running.value
        #expect(harness.todos.count == 1)
    }

    // MARK: - #48 A later start

    @Test("A Tide action that starts on a later day is planned for that day here")
    func laterStartIsPlanned() async throws {
        let harness = try TideSyncHarness()
        let later = harness.tide.add("Order bead chains", in: FakeTide.roomSetup, heading: nil, start: "2026-10-26")
        let started = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil, start: "2026-10-12")

        await harness.run()

        #expect(harness.todo(linkedTo: later)?.scheduledDate == (try CoreDataTestHelpers.day("2026-10-26")))
        #expect(harness.todo(linkedTo: started)?.scheduledDate == nil, "started already: due now")
    }

    // MARK: - #51 Known by address only

    @Test("Known by address only and reworded in Tide: the copy follows, and no second one comes")
    func unmarkedRewordFollows() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        harness.tide.refusedNotes = ["Label the shelves"]
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))
        let id = try #require(todo.id)
        #expect(harness.saved.unmarkedLinks.count == 1, "its note couldn't take the line")
        todo.notes = "Use the white tape."
        #expect(CoreDataTestHelpers.save(harness.context))

        harness.tide.reword("Label the shelves", to: "Label the shelves and bins")
        await harness.run()

        #expect(!todo.isCompleted, "not closed")
        #expect(todo.title == "Label the shelves and bins")
        #expect(todo.notes == "Use the white tape.")
        #expect(harness.todos.count == 1, "no fresh copy")
        #expect(harness.tide.action(notebookID: id) != nil, "asked for the line again once the list changed")
    }

    @Test("Known by address only and ticked in Tide while another came: it closes, and the new one comes in")
    func unmarkedTickStillCloses() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        harness.tide.refusedNotes = ["Label the shelves"]
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))

        harness.tide.setState("done", of: "Label the shelves")
        harness.tide.add("Order bead chains", in: FakeTide.roomSetup, heading: nil)
        await harness.run()

        #expect(todo.isCompleted)
        #expect(harness.todos.count == 2)
        #expect(harness.todos.contains { $0.title == "Order bead chains" && !$0.isCompleted })
    }

    @Test("Known by address only and moved to another list: the copy follows")
    func unmarkedMoveFollows() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        harness.tide.refusedNotes = ["Label the shelves"]
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))

        harness.tide.move("Label the shelves", to: FakeTide.areaList)
        await harness.run()

        #expect(!todo.isCompleted)
        #expect(todo.tideLink == TideActionLink(file: FakeTide.areaList, text: "Label the shelves").string)
        #expect(harness.todos.count == 1)
    }

    // MARK: - Helpers

    /// Waits, up to `timeout`, for `condition`.
    private static func eventually(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let end = clock.now + timeout
        while clock.now < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
