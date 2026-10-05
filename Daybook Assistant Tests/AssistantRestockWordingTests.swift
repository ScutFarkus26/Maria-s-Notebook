import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// What the tab reads from what she types, and how it names who changed
// something: her name as it is now, another assistant, the hold menu's header.
@Suite("Assistant Restock: who and what")
@MainActor
struct AssistantRestockWordingTests {

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

    // MARK: - What she types

    @Test("A sentence's closing period is not a link: Kleenex. is Kleenex, Toilet paper. is the staple")
    func trailingPeriod() throws {
        let paper = try staple("Toilet Paper")
        let tab = model()
        #expect(AssistantRestockModel.pastedLink("Kleenex.") == nil)
        #expect(AssistantRestockModel.pastedLink("Mr.Sketch") == nil)
        #expect(AssistantRestockModel.pastedLink("amazon.com/dp/x")?.host() == "amazon.com")
        #expect(AssistantRestockModel.pastedLink("amazon.com/dp/x.")?.absoluteString == "https://amazon.com/dp/x")
        #expect(AssistantRestockModel.pastedLink("https://example.shop/glue") != nil)

        #expect(tab.addNeed("Kleenex.", source: .office, quantity: 1) == .added)
        let kleenex = try #require(tab.officeRun.first)
        #expect(kleenex.title == "Kleenex")
        #expect(kleenex.urlString.isEmpty)

        #expect(tab.staple(named: "Toilet paper.") == paper)
        #expect(tab.addNeed("Toilet paper.", source: .office, quantity: 1) == .markedStaple)
        #expect(paper.level == .out)
    }

    // MARK: - Who and when

    @Test("Another assistant who gave no name reads as another assistant, not your guide")
    func unnamedSecondAssistant() throws {
        let now = try AssistantTestSupport.day("2026-10-03").addingTimeInterval(8 * 3_600)
        let bea = RestockAuthor(role: .assistant, recordName: "_bea")
        let towels = try #require(RestockService.addStaple(
            .init(name: "Paper Towels"), level: .out, by: bea, at: now, in: context
        )).object
        let soap = try #require(RestockService.addStaple(
            .init(name: "Hand Soap"), level: .low, by: Self.guide, at: now, in: context
        )).object
        let anaInClass = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana", ownerRecordName: "_guide")
        let tab = model(now: now, author: anaInClass)
        let time = now.formatted(date: .omitted, time: .shortened)

        #expect(tab.markedBy(towels) == "Another assistant · \(time)")
        #expect(tab.markedBy(soap) == "Your guide · \(time)")
    }

    @Test("A change is stamped with her name as it is at the time, not when the tab opened")
    func authorReadAtWriteTime() throws {
        let paper = try staple("Toilet Paper")
        let previousRecord = ClassroomIdentity.currentUserRecordName
        let previousName = ClassroomIdentity.displayName
        defer {
            ClassroomIdentity.currentUserRecordName = previousRecord
            ClassroomIdentity.displayName = previousName
        }
        ClassroomIdentity.currentUserRecordName = nil
        ClassroomIdentity.displayName = nil
        let tab = AssistantRestockModel.live(context: context, container: nil)
        tab.load()

        // She types her name, and iCloud sends her record name, after the tab was made.
        ClassroomIdentity.currentUserRecordName = "_bea"
        ClassroomIdentity.displayName = "Bea"
        tab.tap(paper)
        #expect(paper.levelChangedByName == "Bea")
        #expect(paper.levelChangedByID == "_bea")
        #expect(tab.markedBy(paper)?.hasPrefix("You · ") == true)
    }

    @Test("The hold menu says Added for a staple never changed, and that the guide orders an ordered one")
    func menuHeaderWording() throws {
        let soap = try staple("Hand Soap")
        let clay = try staple("Air Dry Clay", place: "Art shelf", source: .order)
        let towels = try staple("Paper Towels", level: .out)
        let tab = model()
        tab.setLevel(towels, to: .stocked)

        #expect(tab.menuHeader(soap).hasPrefix("Added "))
        #expect(tab.menuHeader(soap).contains("by your guide · Bathrooms · From the office"))
        #expect(tab.menuHeader(clay).hasSuffix("Art shelf · Your guide orders it"))
        #expect(tab.menuHeader(towels).hasPrefix("Restocked "))
    }
}
