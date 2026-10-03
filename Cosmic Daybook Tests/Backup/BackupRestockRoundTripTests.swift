import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Backup v37 carries Restock: a staple's level, source, link and who set it,
/// and a need's source, staple and who added it. A backup from before (v36 and
/// older) still restores: every order it holds reads as an order, and its
/// staples get levels from their counts.
@Suite("Backup: Restock", .serialized)
@MainActor
struct BackupRestockRoundTripTests {

    private let ana = RestockTestSupport.ana

    @Test("v37: a staple with an open need survives a Replace restore")
    func stapleWithOpenNeedRoundTrips() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let link = try #require(URL(string: OrderLinkCleanerTests.chargerLink))
        let details = RestockService.StapleDetails(name: "Chargers", place: "Office Shelf", source: .order, link: link)
        let staple = try #require(RestockService.addStaple(
            details, level: .low, by: ana, at: RestockTestSupport.at(10), in: source
        )).object
        staple.minimumThreshold = 3
        staple.unit = "packs"
        RestockService.setLevel(staple, to: .out, by: ana, at: RestockTestSupport.at(20), in: source)
        let need = try #require(RestockService.openNeeds(for: staple, in: source).first)
        RestockService.setQuantity(need, to: 4)
        let glue = try #require(RestockService.addOneOff(title: "Glue sticks", by: ana, in: source)).object
        #expect(CoreDataTestHelpers.save(source))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)
        let restored = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: restored, mode: .replace)

        let back = try #require(
            try BackupTestUtil.fetchByID(CDSupply.self, staple.id, entityName: "Supply", in: restored)
        )
        #expect(back.level == .out)
        #expect(back.source == .order)
        #expect(back.urlString == "https://www.amazon.com/dp/B0B2MMB4LJ")
        #expect(back.location == "Office Shelf")
        #expect(back.levelChangedAt == RestockTestSupport.at(20))
        #expect(back.levelChangedByID == "_ana")
        #expect(back.levelChangedByName == "Ana")
        #expect(back.minimumThreshold == 3)
        #expect(back.unit == "packs")

        let needs = RestockService.openNeeds(for: back, in: restored)
        #expect(needs.map(\.id) == [need.id], "the staple's one open need, and only that")
        #expect(needs.first?.source == .order)
        #expect(needs.first?.quantity == 4)
        #expect(needs.first?.addedByID == "_ana")
        #expect(needs.first?.addedByName == "Ana")
        #expect(RestockService.history(for: back, in: restored).map(\.reason) == ["Out · Ana", "Low · Ana"])

        let restoredGlue = try #require(
            try BackupTestUtil.fetchByID(CDOrderItem.self, glue.id, entityName: "OrderItem", in: restored)
        )
        #expect(restoredGlue.source == .office)
        #expect(restoredGlue.supplyID == nil)
    }

    @Test("A v36 backup restores: its orders are orders, and its staples get levels from their counts")
    func olderBackupRestores() async throws {
        let supplyID = UUID(), orderID = UUID()
        let supplyRow = #"{"categoryRaw":"Other","createdAt":"2026-09-01T12:00:00Z","currentQuantity":0,"#
            + #""id":"\#(supplyID.uuidString)","location":"Bathrooms","modifiedAt":"2026-09-01T12:00:00Z","#
            + #""name":"Paper Towels","notes":""}"#
        let orderRow = #"{"createdAt":"2026-09-23T12:00:00Z","id":"\#(orderID.uuidString)","#
            + #""modifiedAt":"2026-09-23T12:00:00Z","notes":"","quantity":2,"requestedFrom":"","#
            + #""title":"Anker Nano Phone Charger","urlString":"https://www.amazon.com/dp/B0B2MMB4LJ"}"#
        let entries = [("Supply", supplyRow), ("OrderItem", orderRow)].map { name, row in
            BackupEntityEntry(entityName: name, storeName: "private", count: 1, ndjson: Data((row + "\n").utf8))
        }
        let decoded = BackupReader.DecodedBackup(
            manifest: BackupArchiveManifest(
                formatVersion: 36, createdAt: Date(),
                appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
            ),
            entries: entries,
            preferences: nil
        )
        let (payload, warnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(warnings.isEmpty, "\(warnings)")
        #expect(payload.orderItems?.count == 1, "a v36 order row decodes without the v37 keys")

        let restored = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        _ = try await BackupService().importPayload(
            payload: payload,
            envelope: BackupEnvelope(
                formatVersion: 36, encrypted: false, createdAt: Date(), fileName: "v36", entityCounts: [:]
            ),
            viewContext: restored,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )

        let order = try #require(
            try BackupTestUtil.fetchByID(CDOrderItem.self, orderID, entityName: "OrderItem", in: restored)
        )
        #expect(order.source == .order)
        #expect(order.addedByName.isEmpty)
        #expect(order.supplyID == nil)
        #expect(order.quantity == 2)

        let towels = try #require(
            try BackupTestUtil.fetchByID(CDSupply.self, supplyID, entityName: "Supply", in: restored)
        )
        #expect(towels.level == .out, "none left: Out, from its count")
        #expect(towels.levelChangedAt != nil)
        #expect(RestockService.openNeeds(for: towels, in: restored).count == 1)
        #expect(!restored.hasChanges, "the restore saved what it mapped")
    }
}
