import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Bug hunt 2026-10-10, Part 1 #24 and #25: what VoiceOver says on a day
// ahead, and what "Try again" does after a Restock save fails.

@Suite("Assistant fixes 2026-10-10 (D): the future-day hint and Restock retries")
@MainActor
struct AssistantFix1010DTests {

    private let stack: CoreDataStack

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    /// A save that fails until told to work.
    final class FailingSave {
        var fails = true

        func save(_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool {
            fails ? false : context.safeSave()
        }
    }

    private func model(_ saver: FailingSave) -> AssistantRestockModel {
        AssistantRestockTestSupport.model(in: context, save: saver.save)
    }

    private func openNeeds(titled title: String) -> [CDOrderItem] {
        RestockService.openNeeds(in: context, store: nil).filter { $0.title == title }
    }

    // MARK: - #24 The future-day hint

    @Test("VoiceOver reads the whole reason once, with one period, then how to change the mark")
    func futureDayHintReadsOnce() {
        let spoken = AttendanceTile.voiceOverHint(
            tapTarget: nil, reason: "You can only mark absences on a future day"
        )
        #expect(spoken == "You can only mark absences on a future day. Touch and hold to change the mark")
        // A reason written with its own period doesn't come out doubled.
        let withPeriod = AttendanceTile.voiceOverHint(
            tapTarget: nil, reason: "You can only mark absences on a future day."
        )
        #expect(withPeriod == spoken)
        #expect(!withPeriod.contains(".."))
        // A tap that marks says so, whatever the reason line.
        #expect(AttendanceTile.voiceOverHint(tapTarget: .present, reason: "Absences only")
            == "Double tap to mark present")
    }

    // MARK: - #25 We need… tapped again after a failed save

    @Test("Tapped again with a new count, We need… saves the new count on one need")
    func retrySavesNewQuantity() {
        let saver = FailingSave()
        let tab = model(saver)
        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 2) == .notSaved)

        saver.fails = false
        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 5) == .added)
        #expect(!context.hasChanges)
        let needs = openNeeds(titled: "Glue sticks")
        #expect(needs.count == 1)
        #expect(needs.first?.quantity == 5)
    }

    @Test("Tapped again with the other source, or a corrected name, We need… leaves one need, as the sheet says")
    func retryReplacesTheUnsavedAdd() {
        let saver = FailingSave()
        let tab = model(saver)
        #expect(tab.addNeed("Glue stick", source: .office, quantity: 1) == .notSaved)
        // Still failing, she corrects the name: still only one waiting.
        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 1) == .notSaved)
        #expect(context.insertedObjects.count { $0 is CDOrderItem } == 1)

        saver.fails = false
        #expect(tab.addNeed("Glue sticks", source: .order, quantity: 1) == .added)
        #expect(openNeeds(titled: "Glue stick").isEmpty)
        let needs = openNeeds(titled: "Glue sticks")
        #expect(needs.count == 1)
        #expect(needs.first?.source == .order)
    }

    @Test("An add that didn't save stays when the sheet closes, and a later sheet's add doesn't replace it")
    func closedSheetKeepsItsAdd() {
        let saver = FailingSave()
        let tab = model(saver)
        #expect(tab.addNeed("Tape", source: .office, quantity: 1) == .notSaved)
        tab.weNeedClosed()

        saver.fails = false
        #expect(tab.addNeed("Scissors", source: .office, quantity: 1) == .added)
        #expect(openNeeds(titled: "Tape").count == 1)
        #expect(openNeeds(titled: "Scissors").count == 1)
    }

    // MARK: - #25 The office run's Try Again

    @Test("Try Again saves a check-off that didn't save, and leaves it checked off")
    func tryAgainKeepsTheCheckOff() throws {
        try AssistantRestockTestSupport.staple("Toilet Paper", level: .out, in: context)
        let saver = FailingSave()
        let tab = model(saver)
        let need = try #require(tab.officeRun.first)
        tab.toggleCheckOff(need)
        #expect(!tab.flush())
        #expect(tab.errorMessage == AssistantRestockModel.saveFailedMessage)
        #expect(tab.errorMessage?.contains("Try again.") == false)

        saver.fails = false
        #expect(tab.flush())
        #expect(tab.errorMessage == nil)
        #expect(need.receivedAt != nil)
        #expect(tab.isCheckedOff(need))
    }

    @Test("Once another save has written the change, Try Again clears the message")
    func tryAgainAfterAnotherSave() throws {
        // A one-off from the office: its check-off writes no history line, so
        // nothing new waits to go into the share once the context is saved.
        _ = try #require(RestockService.addOneOff(
            title: "Tape", source: .office, by: AssistantRestockTestSupport.guide, in: context
        ))
        #expect(context.safeSave())
        let saver = FailingSave()
        let tab = model(saver)
        tab.toggleCheckOff(try #require(tab.officeRun.first))
        #expect(!tab.flush())
        #expect(tab.errorMessage != nil)

        // The attendance grid saves the same context.
        #expect(context.safeSave())
        #expect(tab.flush())
        #expect(tab.errorMessage == nil)
    }
}
