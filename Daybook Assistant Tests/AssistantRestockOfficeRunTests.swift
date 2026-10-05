import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The office run's check-offs and their Undo, a staple whose level and need
// arrived out of step, and what the tab puts into the classroom share.
@Suite("Assistant Restock: office run and sharing")
@MainActor
struct AssistantRestockOfficeRunTests {

    private let stack: CoreDataStack
    private static let guide = AssistantRestockTestSupport.guide

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    @discardableResult
    private func staple(
        _ name: String,
        place: String = "Bathrooms",
        source: RestockSource = .office,
        level: RestockLevel = .stocked
    ) throws -> CDSupply {
        try AssistantRestockTestSupport.staple(name, place: place, source: source, level: level, in: context)
    }

    private func model(
        now: Date = Date(),
        author: RestockAuthor = AssistantRestockTestSupport.ana,
        save: AssistantRestockModel.Save? = nil
    ) -> AssistantRestockModel {
        AssistantRestockTestSupport.model(in: context, now: now, author: author, save: save)
    }

    // MARK: - Check-offs

    @Test("Coming back to the tab forgets this phone's check-offs: no Undo days later")
    func checkOffsForgottenOnReturn() throws {
        let paper = try staple("Toilet Paper", level: .out)
        let tab = model()
        let need = try #require(tab.officeRun.first)
        tab.toggleCheckOff(need)
        tab.flush()
        #expect(tab.isCheckedOff(need))

        tab.forgetCheckOffs()
        #expect(!tab.isCheckedOff(need))
        #expect(tab.officeRun.isEmpty)
        // A stray tap on the old row (still on screen a moment) takes nothing back.
        tab.toggleCheckOff(need)
        #expect(paper.level == .stocked)
        #expect(need.receivedAt != nil)
    }

    @Test("Undo leaves a staple alone once someone has changed it since the check-off")
    func undoOnlyWhileUnchanged() throws {
        let checkedAt = Date()
        let paper = try staple("Toilet Paper", level: .out)
        let tab = model(now: checkedAt)
        let need = try #require(tab.officeRun.first)
        tab.toggleCheckOff(need)
        tab.flush()

        // On the guide's Mac: Low again, and that need checked off too.
        RestockService.setLevel(paper, to: .low, by: Self.guide, at: checkedAt.addingTimeInterval(60), in: context)
        let second = try #require(RestockService.openNeeds(for: paper, in: context).first)
        RestockService.checkOff(second, by: Self.guide, at: checkedAt.addingTimeInterval(120), in: context)
        #expect(context.safeSave())
        let history = tab.history(for: paper).map(\.reason)

        tab.toggleCheckOff(need)
        #expect(paper.level == .stocked)
        #expect(paper.levelChangedByID == "_guide")
        #expect(need.receivedAt != nil)
        #expect(tab.history(for: paper).map(\.reason) == history, "her Restocked line stays")
        #expect(!tab.isCheckedOff(need))
    }

    @Test("A need checked off before its first save stays ticked after it, and Undo still works")
    func checkOffBeforeSave() throws {
        let paper = try staple("Toilet Paper")
        let tab = model()
        tab.tap(paper)
        let need = try #require(tab.officeRun.first)
        #expect(need.objectID.isTemporaryID)

        tab.toggleCheckOff(need)
        tab.flush()
        #expect(!need.objectID.isTemporaryID)
        #expect(tab.isCheckedOff(need))
        #expect(paper.level == .stocked)

        tab.toggleCheckOff(need)
        #expect(paper.level == .low)
        #expect(need.receivedAt == nil)
        #expect(!tab.isCheckedOff(need))
    }

    @Test("An office-run row whose staple reads Stocked has no tag until the staple is Out or Low")
    func stockedStapleTag() throws {
        let towels = try staple("Paper Towels")
        // Its level and its need arrived out of step from another device.
        RestockService.openNeed(for: towels, by: Self.guide, at: Date(), store: nil, in: context)
        #expect(context.safeSave())
        let tab = model()
        let need = try #require(tab.officeRun.first)

        #expect(tab.officeRunCount == 1, "a Stocked staple's open need isn't closed")
        #expect(AssistantRestockStyle.tag(for: tab.staple(for: need)) == nil)
        #expect(AssistantRestockStyle.tag(for: nil) == nil)
        tab.setLevel(towels, to: .out)
        #expect(AssistantRestockStyle.tag(for: tab.staple(for: need))?.text == "Out")
    }

    // MARK: - Out of step, and the share

    @Test("Loading opens the need a Low or Out staple lost, once its level has settled, and shares it")
    func loadOpensMissingNeed() throws {
        let markedAt = Date().addingTimeInterval(-3_600)
        let details = RestockService.StapleDetails(name: "Toilet Paper", place: "Bathrooms")
        let paper = try #require(
            RestockService.addStaple(details, level: .out, by: Self.guide, at: markedAt, in: context)
        ).object
        // Another device checked the need off as the guide marked it Out.
        let need = try #require(RestockService.openNeeds(for: paper, in: context).first)
        OrderService.setReceived([need], true, at: markedAt)
        #expect(context.safeSave())
        let history = RestockService.history(for: paper, in: context).count

        // Just marked: its need may still be on its way from that device.
        let early = model(now: markedAt.addingTimeInterval(60))
        #expect(early.officeRunCount == 0)
        #expect(RestockService.openNeeds(for: paper, in: context).isEmpty)

        let recorder = AssistantRestockTestSupport.ShareRecorder()
        let later = model(now: markedAt.addingTimeInterval(600), save: recorder.save)
        let opened = try #require(RestockService.openNeeds(for: paper, in: context).first)
        #expect(later.officeRunCount == 1)
        #expect(opened.addedByID == "_guide")
        #expect(RestockService.history(for: paper, in: context).count == history, "no line of history")
        #expect(!context.hasChanges)
        #expect(recorder.created.last?.contains(opened) == true)
    }

    @Test("Restock records another save wrote first still go into the share at the tab's save")
    func createdSavedElsewhere() throws {
        let paper = try staple("Toilet Paper")
        let recorder = AssistantRestockTestSupport.ShareRecorder()
        let tab = model(save: recorder.save)
        tab.tap(paper)
        // The attendance grid saves the same context before the tab does.
        #expect(context.safeSave())

        tab.flush()
        let shared = try #require(recorder.created.last)
        #expect(Set(shared.compactMap(\.entity.name)) == ["OrderItem", "SupplyTransaction"])
        #expect(shared.count == 2)
    }
}
