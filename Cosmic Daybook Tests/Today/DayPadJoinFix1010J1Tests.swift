import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, Part 2 #75: two devices that each start the day's pad
/// before syncing leave two rows for the day. Today kept the one edited last
/// and deleted the other with its text; MCP `day_pad` read or overwrote
/// whichever row the store returned first.
@Suite("Day Pad join (fix 10-10 J1)")
@MainActor
struct DayPadJoinFix1010J1Tests {

    private struct Seed {
        let id: UUID
        let createdAt: Date
        let modifiedAt: Date
        let body: String
    }

    private var day: Date { AppCalendar.startOfDay(Date(timeIntervalSince1970: 1_791_460_800)) } // Oct 2026
    private let ipadID = UUID()
    private let macID = UUID()

    private var seeds: [Seed] {
        [
            // Started first on the iPad, but the Mac's was edited last.
            Seed(id: ipadID, createdAt: day.addingTimeInterval(8 * 3600),
                 modifiedAt: day.addingTimeInterval(9 * 3600), body: "Call Maya's dad about the trip."),
            Seed(id: macID, createdAt: day.addingTimeInterval(8 * 3600 + 60),
                 modifiedAt: day.addingTimeInterval(15 * 3600), body: "Order more golden beads.")
        ]
    }

    private func insert(_ seeds: [Seed], in context: NSManagedObjectContext) {
        for seed in seeds {
            let pad = CDDayPad(context: context, day: day)
            pad.id = seed.id
            pad.body = seed.body
            pad.createdAt = seed.createdAt
            pad.modifiedAt = seed.modifiedAt
        }
        #expect(CoreDataTestHelpers.save(context))
    }

    private func pads(in context: NSManagedObjectContext) -> [CDDayPad] {
        context.safeFetch(CDFetchRequest(CDDayPad.self))
    }

    @Test("Both devices' text is kept in the pad started first, and the other row goes")
    func joinsBothTexts() throws {
        let context = try CoreDataTestHelpers.makeContext()
        insert(seeds, in: context)

        let kept = try #require(TodayDataFetcher.fetchDayPad(day: day, context: context))
        #expect(CoreDataTestHelpers.save(context))

        #expect(kept.id == ipadID)
        #expect(kept.body == "Call Maya's dad about the trip.\n\nOrder more golden beads.")
        #expect(pads(in: context).count == 1)
    }

    @Test("Two devices joining the same copies at once keep the same pad with the same text")
    func devicesConverge() throws {
        let mac = try CoreDataTestHelpers.makeContext()
        let iPad = try CoreDataTestHelpers.makeContext()
        insert(seeds, in: mac)
        insert(seeds.reversed(), in: iPad)

        let macKept = try #require(TodayDataFetcher.fetchDayPad(day: day, context: mac))
        let iPadKept = try #require(TodayDataFetcher.fetchDayPad(day: day, context: iPad))

        #expect(macKept.id == iPadKept.id)
        #expect(macKept.body == iPadKept.body)
    }

    @Test("Text the kept pad already has isn't added twice")
    func containedTextNotRepeated() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = seeds[0]
        insert([
            Seed(id: first.id, createdAt: first.createdAt, modifiedAt: first.modifiedAt,
                 body: "Call Maya's dad about the trip.\n\nOrder more golden beads."),
            seeds[1]
        ], in: context)

        let kept = try #require(TodayDataFetcher.fetchDayPad(day: day, context: context))
        #expect(kept.body == "Call Maya's dad about the trip.\n\nOrder more golden beads.")
    }

    @Test("Pads started at the same moment keep the one with the smaller id")
    func tieBreaksOnID() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stamp = day.addingTimeInterval(3600)
        let low = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let high = try #require(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001"))
        insert([
            Seed(id: high, createdAt: stamp, modifiedAt: stamp, body: "B"),
            Seed(id: low, createdAt: stamp, modifiedAt: stamp, body: "A")
        ], in: context)

        let kept = try #require(TodayDataFetcher.fetchDayPad(day: day, context: context))
        #expect(kept.id == low)
        #expect(kept.body == "A\n\nB")
    }

    @Test("MCP day_pad reads the joined pad and saves the join")
    func mcpReadsJoinedPad() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        insert(seeds, in: context)
        let tools = MCPNotebookTools.makeTools(context: { context })
        let tool = try #require(tools.first { $0.name == "day_pad" })
        let iso = MCPNotebookTools.isoDay.string(from: day)

        let text = try await tool.handler(["date": .string(iso)])

        #expect(text.contains("Call Maya's dad about the trip."))
        #expect(text.contains("Order more golden beads."))
        #expect(!context.hasChanges)
        #expect(pads(in: context).count == 1)
    }
}
