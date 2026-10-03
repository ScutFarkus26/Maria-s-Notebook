import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Schema 15's one-time step: staples kept as counts get a level, once, on
/// the lead guide's devices, without undoing a level set since.
@Suite("Restock level backfill")
@MainActor
struct RestockLevelBackfillTests {

    private let guide = RestockTestSupport.guide

    private func makeDefaults() throws -> UserDefaults {
        let suite = "RestockLevelBackfillTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A staple as a schema-14 build left it: a count, and no level.
    private func legacyStaple(
        _ name: String, count: Int64, place: String = "", in context: NSManagedObjectContext
    ) -> CDSupply {
        let supply = CDSupply(context: context)
        supply.name = name
        supply.location = place
        supply.currentQuantity = count
        return supply
    }

    @Test("The live shelf: none left is Out with its need on the office run, anything else Stocked")
    func liveShelf() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let towels = legacyStaple("Paper Towels", count: 0, in: context)
        let paper = legacyStaple("Toilet Paper", count: 0, place: "Bathrooms", in: context)
        let clay = legacyStaple("Air Dry Clay", count: 1, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let now = RestockTestSupport.at(0)
        #expect(RestockLevelBackfill.mapCounts(in: context, by: guide, at: now) == 2)
        #expect(towels.level == .out)
        #expect(paper.level == .out)
        #expect(clay.level == .stocked)
        #expect([towels, paper, clay].allSatisfy { $0.levelChangedAt == now })
        for staple in [towels, paper] {
            let needs = RestockService.openNeeds(for: staple, in: context)
            #expect(needs.count == 1)
            #expect(needs.first?.source == .office)
            #expect(RestockService.history(for: staple, in: context).map(\.reason) == ["Out"])
        }
        #expect(RestockService.openNeeds(for: clay, in: context).isEmpty)
        #expect(RestockService.history(for: clay, in: context).isEmpty)
        #expect(CoreDataTestHelpers.save(context))

        // Run again (another of the guide's devices, later): nothing to do.
        #expect(RestockLevelBackfill.mapCounts(in: context, by: guide, at: RestockTestSupport.at(60)) == 0)
        #expect(!context.hasChanges)
    }

    @Test("A staple whose level was ever set is left alone, whatever its count")
    func setLevelsStand() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let towels = legacyStaple("Paper Towels", count: 0, in: context)
        // Restocked on the Mac after its own run; the count was never touched.
        RestockService.stampLevel(towels, by: guide, at: RestockTestSupport.at(5))
        let added = try #require(RestockService.addStaple(.init(name: "Tissues"), by: guide, in: context)).object
        #expect(added.currentQuantity == 0)
        #expect(CoreDataTestHelpers.save(context))

        #expect(RestockLevelBackfill.mapCounts(in: context, by: guide, at: RestockTestSupport.at(60)) == 0)
        #expect(towels.level == .stocked)
        #expect(added.level == .stocked)
        #expect(RestockTestSupport.allNeeds(in: context).isEmpty)
    }

    @Test("It runs once, on the lead guide's device, after the first download")
    func runsOnceForTheGuide() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let defaults = try makeDefaults()
        let towels = legacyStaple("Paper Towels", count: 0, in: context)
        #expect(CoreDataTestHelpers.save(context))

        FirstDownloadGate.arm(defaults: defaults)
        #expect(RestockLevelBackfill.runIfNeeded(in: context, defaults: defaults) == 0)
        #expect(towels.level == .stocked)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.restockLevelsFromCounts), "waits for the download")

        FirstDownloadGate.open(defaults: defaults)
        #expect(RestockLevelBackfill.runIfNeeded(in: context, defaults: defaults) == 1)
        #expect(towels.level == .out)
        #expect(defaults.bool(forKey: UserDefaultsKeys.restockLevelsFromCounts))
        #expect(CoreDataTestHelpers.save(context))

        // Done on this device: a staple from an older build stays as it came.
        let later = legacyStaple("Toilet Paper", count: 0, in: context)
        #expect(RestockLevelBackfill.runIfNeeded(in: context, defaults: defaults) == 0)
        #expect(later.levelChangedAt == nil)
    }

    @Test("An assistant's notebook never maps the shelf")
    func notOnAnAssistantsDevice() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let defaults = try makeDefaults()
        _ = CoreDataTestHelpers.seedClassroomMembership(in: context, role: .assistant)
        let towels = legacyStaple("Paper Towels", count: 0, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(RestockLevelBackfill.runIfNeeded(in: context, defaults: defaults) == 0)
        #expect(towels.levelChangedAt == nil)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.restockLevelsFromCounts))
    }

    @Test("Staples restored from a backup older than levels get theirs from their counts")
    func afterRestore() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let towels = legacyStaple("Paper Towels", count: 0, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(RestockLevelBackfill.afterRestore(formatVersion: 37, in: context) == 0)
        #expect(towels.levelChangedAt == nil, "a v37 backup carries its levels")
        #expect(RestockLevelBackfill.afterRestore(formatVersion: 36, in: context) == 1)
        #expect(towels.level == .out)
        #expect(!context.hasChanges, "saved")
    }
}
