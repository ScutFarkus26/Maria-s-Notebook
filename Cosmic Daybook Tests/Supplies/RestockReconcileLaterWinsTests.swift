import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A Stocked staple with a need still open: once both have settled, the
/// later of the two wins (plan "Domain logic fixes", A2). A need added after
/// the staple was stocked makes it Low; a staple stocked after its need was
/// added closes the need.
@Suite("Restock: the later of level and need wins")
@MainActor
struct RestockReconcileLaterWinsTests {

    private let guide = RestockTestSupport.guide
    private let ana = RestockTestSupport.ana

    private func at(_ seconds: TimeInterval) -> Date {
        RestockTestSupport.at(seconds)
    }

    /// A staple marked Stocked at `stockedAt` by another device, which hadn't
    /// yet seen the need opened at `needAt`.
    private func stockedWithOpenNeed(
        stockedAt: TimeInterval, needAt: TimeInterval, in context: NSManagedObjectContext
    ) throws -> CDSupply {
        let supply = try RestockTestSupport.staple("Tissues", in: context)
        RestockService.openNeed(for: supply, by: ana, at: at(needAt), store: nil, in: context)
        supply.level = .stocked
        RestockService.stampLevel(supply, by: guide, at: at(stockedAt))
        #expect(CoreDataTestHelpers.save(context))
        return supply
    }

    @Test("A need added after the staple was stocked makes it Low, as its adder, with no history")
    func laterNeedWins() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let tissues = try stockedWithOpenNeed(stockedAt: 10, needAt: 20, in: context)
        let history = try context.count(for: CDFetchRequest(CDSupplyTransaction.self))

        #expect(RestockService.reconcile(in: context, now: at(200)) == 0, "not settled yet")
        #expect(tissues.level == .stocked)

        #expect(RestockService.reconcile(in: context, now: at(400)) == 1)
        #expect(tissues.level == .low)
        #expect(tissues.levelChangedAt == at(20))
        #expect(tissues.levelChangedByID == "_ana")
        #expect(RestockService.openNeeds(for: tissues, in: context).count == 1)
        #expect(try context.count(for: CDFetchRequest(CDSupplyTransaction.self)) == history)
        #expect(CoreDataTestHelpers.save(context))
        #expect(RestockService.reconcile(in: context, now: at(400)) == 0, "a second run finds nothing")
    }

    @Test("A staple stocked after its need was added closes the need")
    func laterLevelWins() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let tissues = try stockedWithOpenNeed(stockedAt: 20, needAt: 10, in: context)

        #expect(RestockService.reconcile(in: context, now: at(400)) == 1)
        #expect(tissues.level == .stocked)
        #expect(RestockService.openNeeds(for: tissues, in: context).isEmpty)
        #expect(CoreDataTestHelpers.save(context))
        #expect(RestockService.reconcile(in: context, now: at(400)) == 0, "a second run finds nothing")
    }
}
