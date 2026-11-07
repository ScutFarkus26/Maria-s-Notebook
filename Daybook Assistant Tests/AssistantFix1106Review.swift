import Foundation
import Testing
@testable import Daybook_Assistant

// Phase 4 review of the 2026-11-06 bug-hunt fixes: the arrival bar's own
// Undo had the same gap as Siri's (#3). After a Reopen Arrival, a second
// Close Arrival's Undo went by the records, where the first close's
// absences still stood, and left the day Late.
@MainActor
@Suite("Assistant fix 1106 review")
struct AssistantFix1106Review {

    @Test("The bar's Undo of a close made after a Reopen Arrival reopens the day again")
    func undoAfterReopenReopens() throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari", "Maya"])
        let model = fixture.model()
        #expect(model.beginLate() == 2)
        #expect(model.returnToArrival())
        #expect(model.phase == .arrival)

        // A child added to the roll since, still unmarked: the second close marks her.
        fixture.classOf(["Noa"])
        model.load()
        #expect(model.beginLate() == 1)
        #expect(model.phase == .late)

        #expect(model.returnToArrival(undo: true))
        #expect(model.phase == .arrival, "Ari's and Maya's absences from the first close still stand")
        #expect(model.unmarkedCount == 1, "Noa, whom the second close marked, is unmarked again")
    }
    // A close on a day not reopened still goes by the records: AssistantFix1103Gr.undoGoesBack.

    @Test("The arrival reminder counts a child with a newer build's status as marked, as the grid does (#11)")
    func reminderUsesTheOneRule() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        #expect(context.safeSave())
        let today = Calendar.current.startOfDay(for: Date())
        let store = CDAttendanceStore(context: context, role: .leadGuide)
        let ariRecord = try #require(try store.ensureRecord(for: ari, on: today))
        #expect(store.updateStatus(ariRecord, to: .present))
        let mayaRecord = try #require(try store.ensureRecord(for: maya, on: today))
        mayaRecord.statusRaw = "excusedByANewerBuild"
        #expect(context.safeSave())
        #expect(ArrivalReminder.isRollComplete(on: today, in: context), "Close Arrival would mark no one")
    }
}
