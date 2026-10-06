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

    @Test("v39: who set each level comes back with its line, linked to its staple by supplyID only")
    func historyWhoRoundTrips() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let staple = try RestockTestSupport.staple("Paper Towels", in: source)
        let guide = RestockTestSupport.guide
        RestockService.setLevel(staple, to: .low, by: ana, at: RestockTestSupport.at(10), in: source)
        RestockService.setLevel(staple, to: .out, by: guide, at: RestockTestSupport.at(20), in: source)
        #expect(CoreDataTestHelpers.save(source))
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)

        let restored = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: restored, mode: .replace)
        let back = try #require(
            try BackupTestUtil.fetchByID(CDSupply.self, staple.id, entityName: "Supply", in: restored)
        )
        let lines = RestockService.history(for: back, in: restored)
        #expect(lines.map(\.reason) == ["Out", "Low · Ana"])
        #expect(lines.map(\.changedByID) == ["_guide", "_ana"])
        #expect(lines.allSatisfy { $0.supply == nil }, "never re-linked through `supply`")

        // Ana renamed herself since: the restored line names her as she is now.
        ClassroomNamesTestSupport.person(
            "_ana", "Annie", role: .assistant, created: RestockTestSupport.at(30), in: restored
        )
        #expect(CoreDataTestHelpers.save(restored))
        let names = ClassroomNames.snapshot(in: restored)
        #expect(lines.map { StapleHistorySheet.line(for: $0, names: names) } == ["Out", "Low · Annie"])
    }

    @Test("A Merge restore puts a missing history line back without linking its staple, already in the share")
    func mergeRestoreLeavesTheStapleUnlinked() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let staple = try RestockTestSupport.staple("Paper Towels", in: source)
        RestockService.setLevel(staple, to: .low, by: ana, at: RestockTestSupport.at(10), in: source)
        #expect(CoreDataTestHelpers.save(source))
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)

        // The notebook as it is now: the staple is there, its line went missing.
        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await BackupTestUtil.importCurrentBackup(from: url, into: target, mode: .replace)
        let there = try #require(
            try BackupTestUtil.fetchByID(CDSupply.self, staple.id, entityName: "Supply", in: target)
        )
        RestockService.history(for: there, in: target).forEach(target.delete)
        #expect(CoreDataTestHelpers.save(target))

        try await BackupTestUtil.importCurrentBackup(from: url, into: target, mode: .merge)
        let line = try #require(RestockService.history(for: there, in: target).first)
        #expect(line.reason == "Low · Ana")
        #expect(line.changedByID == "_ana")
        #expect(line.supply == nil, "filing the line must not carry the shared staple along")
        #expect(((there.value(forKey: "transactions") as? NSSet)?.count ?? 0) == 0)
    }

    @Test("A v38 line without who set it keeps the one already stored; a new one has none")
    func olderLineKeepsStoredWho() async throws {
        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let staple = try RestockTestSupport.staple("Paper Towels", in: target)
        RestockService.setLevel(staple, to: .low, by: ana, at: RestockTestSupport.at(10), in: target)
        #expect(CoreDataTestHelpers.save(target))
        let stored = try #require(RestockService.history(for: staple, in: target).first)
        let storedID = try #require(stored.id)
        let supplyID = try #require(staple.id?.uuidString)
        let newID = UUID()

        let rows = [storedID, newID].map { id in
            #"{"date":"2026-09-30T12:00:00Z","id":"\#(id.uuidString)","quantityChange":0,"#
                + #""reason":"Low · Ana","supplyID":"\#(supplyID)"}"#
        }
        let entry = BackupEntityEntry(
            entityName: "SupplyTransaction", storeName: "shared", count: 2,
            ndjson: Data((rows.joined(separator: "\n") + "\n").utf8)
        )
        let decoded = BackupReader.DecodedBackup(
            manifest: BackupArchiveManifest(
                formatVersion: 38, createdAt: Date(),
                appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
            ),
            entries: [entry],
            preferences: nil
        )
        let (payload, warnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(warnings.isEmpty, "\(warnings)")
        _ = try await BackupService().importPayload(
            payload: payload,
            envelope: BackupEnvelope(
                formatVersion: 38, encrypted: false, createdAt: Date(), fileName: "v38", entityCounts: [:]
            ),
            viewContext: target,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )

        #expect(stored.changedByID == "_ana", "a v38 row has no changedByID to put over it")
        let added = try #require(
            try BackupTestUtil.fetchByID(CDSupplyTransaction.self, newID, entityName: "SupplyTransaction", in: target)
        )
        #expect(added.changedByID == "")
        #expect(added.reason == "Low · Ana")
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
