import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What the Restock page and Today's Restock card say: the office run and the
/// to-order list read from open needs, the header line, the card's title and
/// names, and an asked-for request's line.
@Suite("Restock: page and Today card")
@MainActor
struct RestockPageTests {

    private let guide = RestockTestSupport.guide
    private let ana = RestockTestSupport.ana

    private func at(_ seconds: TimeInterval) -> Date {
        RestockTestSupport.at(seconds)
    }

    /// Toilet Paper (office) Out, Air Dry Clay (order) Low, Glue sticks ×12
    /// from the office, and two chargers to order: in that order.
    private func seededContext() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeContext()
        let paper = try RestockTestSupport.staple("Toilet Paper", place: "Bathrooms", in: context)
        let clay = try RestockTestSupport.staple("Air Dry Clay", source: .order, in: context)
        RestockService.setLevel(paper, to: .out, by: ana, at: at(10), in: context)
        RestockService.setLevel(clay, to: .low, by: guide, at: at(20), in: context)
        _ = try #require(RestockService.addOneOff(
            title: "Glue sticks", quantity: 12, by: guide, at: at(30), in: context
        ))
        _ = try #require(RestockService.addOneOff(
            title: "Anker Nano 30W USB-C Charger",
            link: URL(string: "https://www.amazon.com/dp/B0B2MMB4LJ?tag=abc"),
            quantity: 2,
            by: guide,
            at: at(40),
            in: context
        ))
        return context
    }

    @Test("Open needs split into the office run and to order, with staples' levels")
    func digestSplitsBySource() throws {
        let context = try seededContext()
        let digest = TodayRestockLoader.digest(in: context)

        #expect(digest.officeRun.map(\.label) == ["Toilet Paper", "Glue sticks ×12"])
        #expect(digest.officeRun.map(\.level) == [.out, nil])
        #expect(digest.toOrder.map(\.label) == ["Air Dry Clay", "Anker Nano 30W USB-C Charger ×2"])
        #expect(digest.toOrder.map(\.level) == [.low, nil])
    }

    @Test("The header and Today's card count both lists and name the first three")
    func digestWords() throws {
        let digest = TodayRestockLoader.digest(in: try seededContext())

        #expect(digest.headerLine == "4 things: 2 from the office, 2 to order")
        #expect(digest.cardTitle == "Restock: 2 for the office run, 2 to order")
        #expect(digest.cardSubtitle == "Toilet Paper, Glue sticks ×12, Air Dry Clay and 1 more")
    }

    @Test("Nothing needed: no card, and the header says so")
    func emptyDigest() throws {
        let context = try CoreDataTestHelpers.makeContext()
        _ = try RestockTestSupport.staple("Paper Towels", in: context)
        let digest = TodayRestockLoader.digest(in: context)

        #expect(digest.isEmpty)
        #expect(digest.cardTitle == nil)
        #expect(digest.headerLine == "Nothing needed")
        #expect(TodaySectionVisibility.showsRestock(officeRun: digest.officeRun.count, toOrder: digest.toOrder.count)
            == false)
    }

    @Test("A checked-off need leaves the card; one list alone names only that list")
    func checkedOffLeavesTheCard() throws {
        let context = try seededContext()
        for need in RestockService.openNeeds(in: context) where need.source == .office {
            RestockService.checkOff(need, by: guide, at: at(50), in: context)
        }
        let digest = TodayRestockLoader.digest(in: context)

        #expect(digest.officeRun.isEmpty)
        #expect(digest.cardTitle == "Restock: 2 to order")
        #expect(digest.headerLine == "2 things: 0 from the office, 2 to order")
    }

    @Test("A staple's need shows its count only as a one-off would not")
    func stapleNeedHasNoCount() {
        let staple = RestockDigest.Line(title: "Paper Towels", quantity: 3, level: .out)
        let oneOff = RestockDigest.Line(title: "Paper Towels", quantity: 3, level: nil)
        let single = RestockDigest.Line(title: "USB Hub", quantity: 1, level: nil)

        #expect(staple.label == "Paper Towels")
        #expect(oneOff.label == "Paper Towels ×3")
        #expect(single.label == "USB Hub")
    }

    @Test("An asked-for request says when, to whom, and how long it has waited")
    func requestLine() {
        let asked = at(0)
        let request = OrderRequestGroup(id: "r1", requestedAt: asked, requestedFrom: "Ms. Levin", items: [])
        let threeDaysLater = AppCalendar.shared.date(byAdding: .day, value: 3, to: asked) ?? asked
        let day = DateFormatters.shortMonthDay.string(from: asked)

        #expect(RestockView.requestLine(request, now: threeDaysLater) == "Asked \(day) · Ms. Levin · waiting 3 days")
        #expect(RestockView.requestLine(request, now: asked) == "Asked \(day) · Ms. Levin · waiting since today")
    }

    @Test("The Restock day card opens Restock; the lesson card still opens To Schedule")
    func dayCardDestinations() {
        #expect(TodayView.DayCard.restock.destination == .section(.supplies))
        #expect(TodayView.DayCard.needsLesson.destination == .lessonsAndWork(.toSchedule))
        #expect(TodayView.DayCard.allCases == [.needsLesson, .restock])
    }
}
