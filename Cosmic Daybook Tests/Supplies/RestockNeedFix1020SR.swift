import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Daybook Assistant bug hunt 2026-10-20, #27: two devices each opened a need
/// for the same staple, and the merge kept the oldest as it was, so the
/// quantity and note the assistant chose on the newer copy were lost. Until
/// the office is asked, the kept need takes the largest quantity and joins
/// the notes of the copies going, the same way on every device.
@Suite("Restock: needs (Fix1020 SR)")
@MainActor
struct RestockNeedFix1020SRTests {

    private func at(_ seconds: TimeInterval) -> Date {
        RestockTestSupport.at(seconds)
    }

    @Test("Merging needs not yet asked for keeps the largest quantity and every note")
    func mergeKeepsLargestQuantityAndNotes() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let towels = try RestockTestSupport.staple("Paper Towels", place: "", source: .office, link: nil, in: context)
        let supplyID = try #require(towels.id?.uuidString)
        func need(created: Date, quantity: Int64, notes: String) -> CDOrderItem {
            let item = CDOrderItem(context: context)
            item.title = "Paper Towels"
            item.source = .office
            item.supplyID = supplyID
            item.createdAt = created
            item.modifiedAt = created
            item.quantity = quantity
            item.notes = notes
            return item
        }
        let older = need(created: at(10), quantity: 1, notes: "")
        let newer = need(created: at(20), quantity: 4, notes: "The big rolls")
        let newest = need(created: at(30), quantity: 2, notes: "From the closet")
        #expect(CoreDataTestHelpers.save(context))

        #expect(RestockService.reconcile(in: context) == 2)
        #expect(newer.isDeleted && newest.isDeleted)
        #expect(older.quantity == 4)
        #expect(older.notes == "The big rolls · From the closet")
        #expect(older.modifiedAt == at(30))
        #expect(older.requestedAt == nil)
    }

    @Test("Merging copies that say the same thing changes nothing on the kept one")
    func mergeOfSameCopiesLeavesKeptAlone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let towels = try RestockTestSupport.staple("Paper Towels", place: "", source: .office, link: nil, in: context)
        let supplyID = try #require(towels.id?.uuidString)
        func need(created: Date) -> CDOrderItem {
            let item = CDOrderItem(context: context)
            item.title = "Paper Towels"
            item.source = .office
            item.supplyID = supplyID
            item.createdAt = created
            item.modifiedAt = created
            item.quantity = 3
            item.notes = "Big"
            return item
        }
        let older = need(created: at(10))
        _ = need(created: at(20))
        #expect(CoreDataTestHelpers.save(context))

        #expect(RestockService.reconcile(in: context) == 1)
        #expect(older.quantity == 3)
        #expect(older.notes == "Big")
        #expect(older.modifiedAt == at(10))
    }
}
