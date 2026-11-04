import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What a restore does with a staple's Restock fields, and with a row the
/// lenient readers take without its dates, since "Simplify round two",
/// Phase 7 moved their rows onto row specs. The spec oracle restores the
/// golden row into a store already holding the same values, so a rule
/// between two keys, a raw that isn't one, or a value made as the row is
/// read doesn't show there:
///
/// - Who set a staple's level, and when, restore only with the level: a row
///   without `levelRaw` (from before v37) leaves all three as they are; one
///   with it sets each, clearing one it lacks.
/// - A staple's category goes out through the typed category, its level and
///   source as stored; one that isn't one restores as Other, stocked and the
///   office.
/// - A lesson sequence's or a resource's row without its dates reads them as
///   the moment it is read, as the old lenient readers' `?? Date()` did, not
///   as a time fixed once.
@Suite("Backup: a staple's level and who set it, and dates read as now", .serialized)
@MainActor
struct BackupSupplyRestoreTests {

    /// Bea's later change of the staple's level, as a row holds it.
    private static let bea: [String: ModelValue] = [
        "levelChangedAt": .date(Fix1102.at(20)), "levelChangedByID": .string("_bea"),
        "levelChangedByName": .string("Bea")
    ]

    /// A notebook holding one staple, set Low by Ana at 10.
    private static func notebookWithStaple() throws -> (NSManagedObjectContext, UUID) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let staple = CDSupply(context: context)
        staple.name = "Paper Towels"
        staple.levelRaw = RestockLevel.low.rawValue
        staple.levelChangedAt = Fix1102.at(10)
        staple.levelChangedByID = "_ana"
        staple.levelChangedByName = "Ana"
        let stapleID = try #require(staple.id)
        #expect(CoreDataTestHelpers.save(context))
        return (context, stapleID)
    }

    /// A Merge of the notebook's own backup, the staple's row given `setting`
    /// and without `removing`: the staple after it.
    private static func restoreStaple(
        _ stapleID: UUID,
        in context: NSManagedObjectContext,
        setting: [String: ModelValue] = [:],
        removing: Set<String> = []
    ) async throws -> CDSupply {
        var backup = Fix1102.payload(of: context)
        let rows = try #require(backup.supplies)
        let row = try #require(rows.firstIndex { $0.id == stapleID })
        var values = rows[row].values.merging(setting) { $1 }
        for key in removing { values[key] = nil }
        backup.supplies?[row].values = values
        try await Fix1102.restore(backup, into: context, mode: .merge)
        let back = try BackupTestUtil.fetchByID(CDSupply.self, stapleID, entityName: "Supply", in: context)
        return try #require(back)
    }

    @Test("A staple's row without a level leaves who set it, and when, as they are")
    func rowWithoutLevelKeepsWhoSetIt() async throws {
        let (context, stapleID) = try Self.notebookWithStaple()
        let back = try await Self.restoreStaple(stapleID, in: context, setting: Self.bea, removing: ["levelRaw"])
        #expect(back.level == .low, "a row without a level leaves the staple's")
        #expect(back.levelChangedAt == Fix1102.at(10), "and when it was set")
        #expect(back.levelChangedByID == "_ana", "and who set it")
        #expect(back.levelChangedByName == "Ana")
    }

    @Test("A staple's row with a level sets who set it, and when")
    func rowWithLevelSetsWhoSetIt() async throws {
        let (context, stapleID) = try Self.notebookWithStaple()
        var setting = Self.bea
        setting["levelRaw"] = .string(RestockLevel.out.rawValue)
        let back = try await Self.restoreStaple(stapleID, in: context, setting: setting)
        #expect(back.level == .out)
        #expect(back.levelChangedAt == Fix1102.at(20), "a row with a level sets when it was set")
        #expect(back.levelChangedByID == "_bea", "and who set it")
        #expect(back.levelChangedByName == "Bea")
    }

    @Test("A staple's row with a level and no one named clears who set it, and when")
    func rowWithLevelClearsWhoSetIt() async throws {
        let (context, stapleID) = try Self.notebookWithStaple()
        let back = try await Self.restoreStaple(stapleID, in: context, removing: Set(Self.bea.keys))
        #expect(back.level == .low)
        #expect(back.levelChangedAt == nil, "a row with a level and no date clears it")
        #expect(back.levelChangedByID == nil, "and no one clears who")
        #expect(back.levelChangedByName == "", "and the name goes back to none")
    }

    @Test("A staple's category goes out typed, its level and source as stored; each restores as its default")
    func rawsThatArentOneRestoreAsDefaults() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let staple = CDSupply(context: context)
        staple.name = "Glue sticks"
        staple.categoryRaw = "Snacks"
        staple.levelRaw = "brimming"
        staple.sourceRaw = "the moon"
        let stapleID = try #require(staple.id)
        #expect(CoreDataTestHelpers.save(context))

        let backup = Fix1102.payload(of: context)
        let row = try #require(backup.supplies?.first { $0.id == stapleID })
        #expect(row.string("categoryRaw") == SupplyCategory.other.rawValue, "written through the typed category")
        #expect(row.string("levelRaw") == "brimming", "written as stored")
        #expect(row.string("sourceRaw") == "the moon", "written as stored")

        try await Fix1102.restore(backup, into: context, mode: .merge)
        let back = try #require(
            try BackupTestUtil.fetchByID(CDSupply.self, stapleID, entityName: "Supply", in: context)
        )
        #expect(back.categoryRaw == SupplyCategory.other.rawValue)
        #expect(back.levelRaw == RestockLevel.stocked.rawValue)
        #expect(back.sourceRaw == RestockSource.office.rawValue)
    }

    @Test("A sequence's or a resource's row without its dates reads them as the moment it is read")
    func missingDatesReadAsNow() async throws {
        // A date fixed once would be made here, before `start`.
        _ = (SequenceTrackBackupRow.spec, ResourceBackupRow.spec)
        try await Task.sleep(for: .milliseconds(20))
        let start = Date()
        let line = Data(#"{"id":"\#(UUID().uuidString)"}"#.utf8)

        let track = try JSONDecoder().decode(SequenceTrackDTO.self, from: line)
        #expect(Self.date(track.values["createdAt"]).map { $0 >= start } == true, "created as it is read")
        #expect(track.values["isSequential"] == .bool(true), "taken in order")
        #expect(track.values["area"] == .string(""))

        let resource = try JSONDecoder().decode(ResourceDTO.self, from: line)
        #expect(Self.date(resource.values["createdAt"]).map { $0 >= start } == true, "created as it is read")
        #expect(Self.date(resource.values["modifiedAt"]).map { $0 >= start } == true, "changed as it is read")
        #expect(resource.rowModifiedAt.map { $0 >= start } == true, "a Merge weighs it as changed now")
        #expect(resource.values["categoryRaw"] == .string(""))
        #expect(resource.values["tags"] == .strings([]))
    }

    private static func date(_ value: ModelValue?) -> Date? {
        if case .date(let date)? = value { date } else { nil }
    }
}
