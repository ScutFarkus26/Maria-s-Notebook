import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Daybook Assistant bug hunt 2026-10-20, the Restock tab: a tap on a staple
// the guide just deleted (#30), history that named nobody for an assistant
// with no name (#31), a stale "Couldn't save" after a later save worked, a
// "We need…" for a one-off already listed that ignored the new quantity, and
// the sample class's Siri tip (#33).
@Suite("Assistant Restock (Fix1020 SR)")
@MainActor
struct AssistantRestockFix1020SRTests {

    private let stack: CoreDataStack

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    private func model(save: AssistantRestockModel.Save? = nil) -> AssistantRestockModel {
        AssistantRestockTestSupport.model(in: context, save: save)
    }

    // MARK: - #30 A staple that's gone

    @Test("A tap or a level on a staple the guide deleted does nothing and reloads the shelf")
    func deletedStapleIsLeftAlone() throws {
        let towels = try AssistantRestockTestSupport.staple("Paper Towels", in: context)
        let tab = model()
        #expect(tab.staples.contains(towels))
        // Deleted while the tile is up (the guide's delete arriving).
        context.delete(towels)
        #expect(AssistantRestockModel.isGone(towels))

        #expect(!tab.tap(towels))
        tab.setLevel(towels, to: .out)
        #expect(context.insertedObjects.isEmpty, "no need or history line without its staple")
        #expect(!tab.staples.contains(towels))
    }

    @Test("A note on a staple that's gone is dropped")
    func noteOnDeletedStaple() throws {
        let towels = try AssistantRestockTestSupport.staple("Paper Towels", in: context)
        let tab = model()
        context.delete(towels)
        #expect(AssistantRestockModel.isGone(towels))

        tab.setNote("The big rolls", for: towels)
        #expect(towels.notes.isEmpty)
    }

    // MARK: - #31 History for someone with no name

    @Test("History names who made a change when they set no name")
    func historyNamesUnnamedPeople() throws {
        let towels = try AssistantRestockTestSupport.staple("Paper Towels", in: context)
        let mine = RestockAuthor(role: .assistant, recordName: "_ana", ownerRecordName: "_guide")
        let other = RestockAuthor(role: .assistant, recordName: "_bea")
        let guide = RestockAuthor(role: .leadGuide, recordName: "_guide")
        RestockService.setLevel(towels, to: .low, by: mine, at: Date(timeIntervalSince1970: 10), in: context)
        RestockService.setLevel(towels, to: .out, by: other, at: Date(timeIntervalSince1970: 20), in: context)
        RestockService.setLevel(towels, to: .stocked, by: guide, at: Date(timeIntervalSince1970: 30), in: context)
        #expect(context.safeSave())

        let lines = RestockService.history(for: towels, in: context).map {
            AssistantRestockHistorySheet.line(for: $0, names: mine.names, reader: mine)
        }
        #expect(lines == ["Restocked · Your guide", "Out · Another assistant", "Low · You"])

        // A name set in the classroom's list still wins, and a counted
        // change with no one stamped reads as written.
        AssistantRestockTestSupport.person("_guide", "Danny", role: .leadGuide, in: context)
        let reading = mine.reading(ClassroomNames.snapshot(in: context))
        let named = RestockService.history(for: towels, in: context).map {
            AssistantRestockHistorySheet.line(for: $0, names: reading.names, reader: reading)
        }
        #expect(named.first == "Restocked · Danny")
        RestockService.setCount(towels, to: 3, reason: "Counted", in: context)
        let counted = try #require(RestockService.history(for: towels, in: context).first { $0.reason == "Counted" })
        #expect(AssistantRestockHistorySheet.line(for: counted, names: mine.names, reader: mine) == "Counted")
    }

    // MARK: - #33 Smaller

    /// A save that fails until told to work.
    final class FailingSave {
        var fails = true

        func save(_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool {
            fails ? false : context.safeSave()
        }
    }

    @Test("A later save that works clears the Couldn't save banner")
    func laterSaveClearsBanner() async throws {
        let towels = try AssistantRestockTestSupport.staple("Paper Towels", in: context)
        let failing = FailingSave()
        let tab = model(save: failing.save)
        let following = Task { await tab.followSaves() }
        defer { following.cancel() }
        try await Task.sleep(for: .milliseconds(50))

        tab.tap(towels)
        #expect(!tab.flush())
        #expect(tab.errorMessage != nil)

        // The attendance grid saves the same context, and it works now.
        failing.fails = false
        #expect(context.safeSave())
        for _ in 0..<100 where tab.errorMessage != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(tab.errorMessage == nil)
    }

    @Test("We need… on a one-off already listed raises its quantity to the larger one")
    func weNeedRaisesQuantity() throws {
        let tab = model()
        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 1) == .added)
        let need = try #require(RestockService.openNeeds(in: context).first)

        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 4) == .updatedQuantity)
        #expect(need.quantity == 4)
        #expect(!context.hasChanges)

        // A smaller count leaves it.
        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 2) == .alreadyListed)
        #expect(need.quantity == 4)
        #expect(RestockService.openNeeds(in: context).count == 1)
    }

    @Test("The join screen's sample class doesn't offer the Siri tip, which can't work there")
    func sampleHidesSiriTip() {
        #expect(!AssistantWeNeedSheet.showsSiriTip(sampleChosen: true))
        #expect(AssistantWeNeedSheet.showsSiriTip(sampleChosen: false))
    }
}
