import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// "We need…" naming a staple with a quantity, and what the tab does when a
// save fails: the sheet stays open and the office run says so (bug hunt
// 2026-10-09 #21, #26).
@Suite("Assistant Restock: We need… and saves that fail")
@MainActor
struct AssistantRestockSaveTests {

    private let stack: CoreDataStack

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    @discardableResult
    private func staple(
        _ name: String,
        place: String = "Bathrooms",
        level: RestockLevel = .stocked
    ) throws -> CDSupply {
        try AssistantRestockTestSupport.staple(name, place: place, level: level, in: context)
    }

    private func model(save: AssistantRestockModel.Save? = nil) -> AssistantRestockModel {
        AssistantRestockTestSupport.model(in: context, save: save)
    }

    /// A save that fails until told to work.
    final class FailingSave {
        var fails = true

        func save(_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool {
            fails ? false : context.safeSave()
        }
    }

    @Test("Naming a staple puts her chosen quantity on its need, until the guide has asked for it")
    func weNeedStapleQuantity() throws {
        let towels = try staple("Paper Towels", place: "Sink")
        let tab = model()

        #expect(tab.addNeed("Paper towels", source: .office, quantity: 4) == .markedStaple)
        let need = try #require(RestockService.openNeeds(for: towels, in: context).first)
        #expect(need.quantity == 4)
        #expect(!context.hasChanges)

        // The default of one leaves the count she set.
        #expect(tab.addNeed("Paper towels", source: .office, quantity: 1) == .markedStaple)
        #expect(need.quantity == 4)

        // Once the guide has asked for it (an order), what was asked stands.
        need.source = .order
        RestockService.markRequested([need], from: "Office")
        #expect(context.safeSave())
        #expect(need.requestedAt != nil)
        #expect(tab.addNeed("Paper towels", source: .office, quantity: 9) == .markedStaple)
        #expect(need.quantity == 4)
        #expect(RestockService.openNeeds(for: towels, in: context).count == 1)
    }

    @Test("A We need… that doesn't save says so and keeps the sheet's add; the same add again saves it once")
    func weNeedSaveFails() throws {
        let saver = FailingSave()
        let tab = model(save: saver.save)

        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 2) == .notSaved)
        #expect(tab.errorMessage == "Couldn't save that change. Try again.")
        #expect(context.hasChanges)

        // Tapped again, still failing: still not saved, not "already on the list".
        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 2) == .notSaved)

        saver.fails = false
        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 2) == .added)
        #expect(tab.errorMessage == nil)
        #expect(!context.hasChanges)
        #expect(tab.officeRun.count { $0.title == "Glue sticks" } == 1)
        // Now saved, the same add is a duplicate.
        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 2) == .alreadyListed)
    }

    @Test("Marking a staple Out that doesn't save says so")
    func weNeedStapleSaveFails() throws {
        let towels = try staple("Paper Towels", place: "Sink")
        let saver = FailingSave()
        let tab = model(save: saver.save)

        #expect(tab.addNeed("Paper towels", source: .office, quantity: 3) == .notSaved)
        #expect(tab.errorMessage != nil)
        #expect(towels.level == .out)

        saver.fails = false
        #expect(tab.addNeed("Paper towels", source: .office, quantity: 3) == .markedStaple)
        #expect(!context.hasChanges)
        #expect(RestockService.openNeeds(for: towels, in: context).first?.quantity == 3)
    }

    @Test("A check-off that doesn't save leaves the error for the office run to show")
    func officeRunSaveFails() throws {
        try staple("Toilet Paper", level: .out)
        let saver = FailingSave()
        let tab = model(save: saver.save)
        tab.toggleCheckOff(try #require(tab.officeRun.first))
        #expect(!tab.flush())
        #expect(tab.errorMessage == "Couldn't save that change. Try again.")
        saver.fails = false
        #expect(tab.flush())
        #expect(tab.errorMessage == nil)
    }
}
