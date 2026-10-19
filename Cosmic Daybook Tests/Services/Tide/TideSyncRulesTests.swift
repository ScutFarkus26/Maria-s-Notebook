import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The review's fixes to what goes across and when: work check-ins and
/// parked actions at the first run, Someday and later days, refusals that
/// pass by themselves, a heading gone, repeats on both sides, and how much
/// the sync remembers.
@Suite("Tide sync: what goes across, and when", .serialized)
@MainActor
struct TideSyncRulesTests {

    @Test("The first run links a work check-in (never sent) and matches waiting and someday actions")
    func firstRunMatchesCheckInsAndParkedActions() async throws {
        let harness = try TideSyncHarness(confirmed: false)
        harness.tide.add("Check in with Maya on fractions", in: FakeTide.roomSetup, heading: nil)
        harness.tide.setState("waiting", of: "Check in with Maya on fractions")
        harness.tide.add("Order more beads", in: FakeTide.roomSetup, heading: nil)
        harness.tide.setState("someday", of: "Order more beads")
        let checkIn = harness.todo("Check in with Maya on fractions", workID: UUID())
        let beads = harness.todo("Order beads")

        guard case .needsFirstRunOK(let proposal) = await harness.run() else { Issue.record("no proposal"); return }
        #expect(Set(proposal.matches.map(\.notebookID)) == Set([checkIn.id, beads.id].compactMap { $0 }))
        #expect(proposal.matches.first { $0.notebookID == checkIn.id }?.isCheckIn == true)
        #expect(proposal.toSend == 0)

        _ = await harness.engine.confirmFirstRun(proposal.matches, settings: harness.settings, now: harness.now)
        #expect(checkIn.tideLink != nil)
        #expect(beads.tideLink != nil)
        #expect(!harness.tide.callNames.contains("add_action"), "a check-in is linked, never sent")

        TodoCompletionService.complete(checkIn)
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()
        #expect(harness.tide.action("Check in with Maya on fractions")?.state == "done", "its tick goes across")
    }

    @Test("Someday stays here; a later planned day goes as Tide's start")
    func somedayAndStart() async throws {
        let harness = try TideSyncHarness()
        let someday = harness.todo("Learn the ukulele")
        someday.isSomeday = true
        let later = harness.todo("Plan the field trip")
        later.scheduledDate = try CoreDataTestHelpers.day("2026-10-25")
        let today = harness.todo("Email the art teacher")
        today.scheduledDate = harness.now
        #expect(CoreDataTestHelpers.save(harness.context))

        await harness.run()

        #expect(someday.tideLink == nil)
        #expect(harness.tide.action("Learn the ukulele") == nil)
        #expect(harness.tide.action("Plan the field trip")?.start == "2026-10-25")
        #expect(harness.tide.action("Email the art teacher")?.start == nil)
    }

    @Test("Not in Tide's store yet: tried again next run, not called a refusal")
    func temporaryRefusalIsRetried() async throws {
        let harness = try TideSyncHarness()
        let todo = harness.todo("Plan the field trip")
        harness.tide.notReadyOnce = ["Plan the field trip"]

        guard case .synced(let first) = await harness.run() else { Issue.record("not synced"); return }
        #expect(first.tryAgain)
        #expect(first.notSent.isEmpty)
        #expect(todo.tideLink == nil)

        await harness.run()
        #expect(todo.tideLink != nil)
    }

    @Test("A saved heading gone from the list says so, and sending resumes once it's picked again")
    func headingGone() async throws {
        let harness = try TideSyncHarness()
        harness.tide.add("Order pin maps")
        harness.tide.headings[FakeTide.upperEl] = ["This week"]
        harness.settings.destinationHeading = "Next week"
        let todo = harness.todo("Plan the field trip")

        guard case .synced(let report) = await harness.run() else { Issue.record("not synced"); return }
        #expect(report.headingGone == "Next week")
        #expect(report.notSent.isEmpty)
        #expect(TideSyncMessages.headingGone("Next week", list: "Upper Elementary")
            == "The heading “Next week” isn't in Tide's Upper Elementary list any more. Pick another in Settings.")
        #expect(todo.tideLink == nil)

        harness.settings.destinationHeading = nil
        await harness.run()
        #expect(todo.tideLink != nil)
    }

    @Test("A repeat on both sides: the tick goes across before anything is sent, so nothing is left behind in Tide")
    func repeatOnBothSides() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Water the plants", in: FakeTide.roomSetup, heading: nil,
                                    due: "2026-10-19", repeats: true)
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))
        todo.recurrence = .weekly
        #expect(CoreDataTestHelpers.save(harness.context))

        TodoCompletionService.complete(todo)
        #expect(CoreDataTestHelpers.save(harness.context))
        await harness.run()

        #expect(!harness.tide.callNames.contains("add_action"), "the next occurrence isn't sent and orphaned")
        #expect(harness.tide.actions.count == 1)
        #expect(!todo.isCompleted)
        #expect(harness.todos.filter { !$0.isCompleted }.count == 1)
    }

    @Test("Unticking a repeat keeps a next occurrence that is already in Tide")
    func reopenKeepsSentOccurrence() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let todo = CDTodoItem(context: context)
        todo.title = "Water the plants"
        todo.recurrence = .weekly
        todo.dueDate = try CoreDataTestHelpers.day("2026-10-19")
        TodoCompletionService.complete(todo)
        let next = try #require(context.safeFetch(CDFetchRequest(CDTodoItem.self)).first { !$0.isCompleted })
        next.tideLink = TideActionLink(file: FakeTide.upperEl, text: "Water the plants").string

        TodoCompletionService.reopen(todo)

        #expect(!next.isDeleted)
        #expect(context.safeFetch(CDFetchRequest(CDTodoItem.self)).count == 2)
    }

    @Test("What the sync remembers stays bounded: a to-do closed on both sides is forgotten")
    func rememberedStatesStayBounded() async throws {
        let harness = try TideSyncHarness()
        let link = harness.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        await harness.run()
        let todo = try #require(harness.todo(linkedTo: link))
        let id = try #require(todo.id).uuidString
        #expect(harness.saved.agreedOpen[id] == true)
        #expect(harness.saved.fromTide.contains(id))

        harness.tide.setState("done", of: "Label the shelves")
        await harness.run()
        #expect(todo.isCompleted)
        #expect(harness.saved.agreedOpen[id] == nil)

        await harness.run()
        #expect(harness.saved.agreedOpen.isEmpty)
        #expect(harness.saved.fromTide.isEmpty)
    }

    @Test("An open to-do whose state was lost isn't ticked off when its action is gone")
    func unknownStateIsLeftOpen() async throws {
        let harness = try TideSyncHarness()
        let todo = harness.todo("Plan the field trip")
        todo.tideLink = TideActionLink(file: FakeTide.upperEl, text: "Plan the field trip").string
        #expect(CoreDataTestHelpers.save(harness.context))

        await harness.run()

        #expect(!todo.isCompleted)
        #expect(!harness.tide.callNames.contains("add_action"))
    }
}
