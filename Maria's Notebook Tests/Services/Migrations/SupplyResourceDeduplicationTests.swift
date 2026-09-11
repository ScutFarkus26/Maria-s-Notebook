import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// Supplies, their transaction history, and resources folded back into one row.
///
/// Every classroom entity is assigned to both store configurations, so the
/// shared → private clone each device ran copied these rows *with their ids*,
/// and the copies then synced to each other — which is why `list_supplies` was
/// printing three supplies six times. Students and lessons took the same hit and
/// read clean only because they were already in `deduplicateAllModels`.
///
/// The regression that matters here is `Supply.transactions`: it is a **Cascade**
/// relationship, so folding the duplicate without re-parenting its transactions
/// first would delete the shelf's history along with the duplicate row, and the
/// running total would be left with nothing to explain it.
@Suite("Supply and resource deduplication")
@MainActor
struct SupplyResourceDeduplicationTests {

    private func makeSupply(
        in context: NSManagedObjectContext,
        id: UUID,
        name: String,
        quantity: Int64,
        createdAt: Date
    ) -> CDSupply {
        let supply = CDSupply(context: context)
        supply.id = id
        supply.name = name
        supply.currentQuantity = quantity
        supply.createdAt = createdAt
        return supply
    }

    @discardableResult
    private func makeTransaction(
        in context: NSManagedObjectContext,
        on supply: CDSupply,
        change: Int64,
        reason: String,
        id: UUID = UUID()
    ) -> CDSupplyTransaction {
        let transaction = CDSupplyTransaction(context: context)
        transaction.id = id
        transaction.supplyID = supply.id?.uuidString ?? ""
        transaction.date = Date()
        transaction.quantityChange = change
        transaction.reason = reason
        transaction.supply = supply
        return transaction
    }

    private func transactions(in context: NSManagedObjectContext) -> [CDSupplyTransaction] {
        context.safeFetch(CDFetchRequest(CDSupplyTransaction.self))
    }

    // MARK: - Supplies

    @Test("One supply survives, and it keeps both copies' history")
    func supplyMergeKeepsTransactions() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let sharedID = UUID()

        let older = makeSupply(
            in: context, id: sharedID, name: "Golden Beads", quantity: 40,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        makeTransaction(in: context, on: older, change: -8, reason: "Used in a lesson")
        let clone = makeSupply(
            in: context, id: sharedID, name: "Golden Beads", quantity: 33,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        makeTransaction(in: context, on: clone, change: -7, reason: "Recounted")
        #expect(CoreDataTestHelpers.save(context))

        let results = DataCleanupService.deduplicateAllModels(using: context)
        #expect(results["Supply"] == 1)

        let survivors = context.safeFetch(CDFetchRequest(CDSupply.self))
        #expect(survivors.count == 1)
        let survivor = try #require(survivors.first)
        // Earliest `createdAt` wins, and its count stands where the two drifted.
        #expect(survivor.currentQuantity == 40)

        // The Cascade regression: neither adjustment may be lost.
        let history = transactions(in: context)
        #expect(history.count == 2)
        #expect(Set(history.map(\.reason)) == ["Used in a lesson", "Recounted"])
        // Both the relationship and the string FK point at the survivor, so the
        // detail screen and the readers agree about whose history this is.
        #expect(history.allSatisfy { $0.supply == survivor })
        #expect(history.allSatisfy { $0.supplyID == sharedID.uuidString })
        let owned = (survivor.value(forKey: "transactions") as? NSSet)?.count
        #expect(owned == 2)
    }

    @Test("Transactions cloned under one id fold in the same pass")
    func duplicateTransactionsFoldToo() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let supplyID = UUID()
        let transactionID = UUID()

        let older = makeSupply(
            in: context, id: supplyID, name: "Pencils", quantity: 100,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        makeTransaction(in: context, on: older, change: -5, reason: "Taken", id: transactionID)
        let clone = makeSupply(
            in: context, id: supplyID, name: "Pencils", quantity: 100,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        makeTransaction(in: context, on: clone, change: -5, reason: "Taken", id: transactionID)
        #expect(CoreDataTestHelpers.save(context))

        let results = DataCleanupService.deduplicateAllModels(using: context)
        #expect(results["Supply"] == 1)
        // Supplies run before transactions, so the re-parented copy is on the
        // survivor by the time the transaction pass reads the table.
        #expect(context.safeFetch(CDFetchRequest(CDSupply.self)).count == 1)
        #expect(transactions(in: context).count == 1)
    }

    @Test("A shelf with no duplicates is left entirely alone")
    func cleanStoreIsUntouched() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        let supply = makeSupply(
            in: context, id: UUID(), name: "Bead Bars", quantity: 12,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        makeTransaction(in: context, on: supply, change: -1, reason: "Used")
        let resource = CDResource(context: context)
        resource.id = UUID()
        resource.title = "Timeline of Life"
        #expect(CoreDataTestHelpers.save(context))

        let results = DataCleanupService.deduplicateAllModels(using: context)
        // `results` only carries entity types that actually shrank, so absence
        // is the assertion: a clean store writes nothing, which matters because
        // every delete this pass makes syncs to the guide's other devices.
        #expect(results["Supply"] == nil)
        #expect(results["SupplyTransaction"] == nil)
        #expect(results["Resource"] == nil)
        #expect(context.safeFetch(CDFetchRequest(CDSupply.self)).count == 1)
        #expect(transactions(in: context).count == 1)
        #expect(context.safeFetch(CDFetchRequest(CDResource.self)).count == 1)
    }

    @Test("Running the pass twice changes nothing the second time")
    func passIsIdempotent() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let sharedID = UUID()

        for offset in 0..<3 {
            let supply = makeSupply(
                in: context, id: sharedID, name: "Sandpaper Letters", quantity: 1,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 + offset))
            )
            makeTransaction(in: context, on: supply, change: 1, reason: "Delivery \(offset)")
        }
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.deduplicateAllModels(using: context)["Supply"] == 2)
        #expect(DataCleanupService.deduplicateAllModels(using: context)["Supply"] == nil)
        #expect(context.safeFetch(CDFetchRequest(CDSupply.self)).count == 1)
        #expect(transactions(in: context).count == 3)
    }

    // MARK: - Resources

    @Test("Resources cloned under one id fold to a single row")
    func resourcesFold() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let sharedID = UUID()

        for offset in 0..<3 {
            let resource = CDResource(context: context)
            resource.id = sharedID
            resource.title = "Parts of the Flower"
            resource.createdAt = Date(timeIntervalSince1970: TimeInterval(1_000 + offset))
        }
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.deduplicateAllModels(using: context)["Resource"] == 2)
        let survivors = context.safeFetch(CDFetchRequest(CDResource.self))
        #expect(survivors.count == 1)
        #expect(survivors.first?.title == "Parts of the Flower")
    }
}
