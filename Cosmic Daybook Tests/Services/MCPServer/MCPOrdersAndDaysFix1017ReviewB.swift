import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, review (b): `update_order_items` stages it can't
/// move to (#9) and the MCP day formatter's zone (#35).
@Suite("MCP orders and days (Fix1017 review b)")
@MainActor
struct MCPOrdersAndDaysFix1017ReviewB {

    private struct Harness {
        let tools: [MCPToolDefinition]
        let context: NSManagedObjectContext
    }

    private func makeHarness() throws -> Harness {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let dependencies = AppDependencies(coreDataStack: stack)
        return Harness(
            tools: MCPNotebookTools.makeTools(context: { context }, dependencies: { dependencies }),
            context: context
        )
    }

    private func call(_ name: String, _ arguments: [String: JSONValue], in harness: Harness) async throws -> String {
        let tool = try #require(harness.tools.first { $0.name == name })
        return try await tool.handler(arguments)
    }

    /// Adds one item to order and returns it with its id.
    private func addItem(in harness: Harness) async throws -> (CDOrderItem, String) {
        _ = try await call("add_order_items", [
            "items": .array([.object(["url": .string("example.com/glue"), "title": .string("Glue sticks")])])
        ], in: harness)
        let item = try #require(harness.context.safeFetch(CDFetchRequest(CDOrderItem.self)).first)
        return (item, try #require(item.id?.uuidString))
    }

    private func setStage(_ stage: String, of id: String, in harness: Harness) async throws -> String {
        try await call("update_order_items", [
            "items": .array([.object(["id": .string(id), "stage": .string(stage)])])
        ], in: harness)
    }

    /// The tool's error for a stage it refuses, or nil when it accepted it.
    private func refusal(setting stage: String, of id: String, in harness: Harness) async -> String? {
        do {
            _ = try await setStage(stage, of: id, in: harness)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - #9 A stage the item can't move to says why

    @Test("#9 asked_for on a confirmed item says it's already confirmed, not \"already as asked\"")
    func askedForOnConfirmed() async throws {
        let harness = try makeHarness()
        let (item, id) = try await addItem(in: harness)
        _ = try await setStage("asked_for", of: id, in: harness)
        _ = try await setStage("confirmed", of: id, in: harness)
        #expect(item.stage == .confirmed)

        let message = await refusal(setting: "asked_for", of: id, in: harness)
        let refused = try #require(message)
        #expect(refused.contains("confirmed"))
        #expect(!refused.contains("already as asked"))
        #expect(item.stage == .confirmed)
    }

    @Test("#9 asked_for or confirmed on a received item says it's already received")
    func earlierStageOnReceived() async throws {
        let harness = try makeHarness()
        let (item, id) = try await addItem(in: harness)
        _ = try await setStage("asked_for", of: id, in: harness)
        _ = try await setStage("received", of: id, in: harness)
        #expect(item.stage == .received)

        for stage in ["asked_for", "confirmed"] {
            let message = await refusal(setting: stage, of: id, in: harness)
            let refused = try #require(message, "\(stage) on a received item")
            #expect(refused.contains("received"))
            #expect(refused.contains("not_received"))
            #expect(!refused.contains("already as asked"))
        }
        #expect(item.stage == .received)
    }

    @Test("#9 A stage the item is already at still changes nothing, without an error")
    func sameStageStillUnchanged() async throws {
        let harness = try makeHarness()
        let (_, id) = try await addItem(in: harness)
        _ = try await setStage("asked_for", of: id, in: harness)
        _ = try await setStage("confirmed", of: id, in: harness)

        let reply = try await setStage("confirmed", of: id, in: harness)
        #expect(reply.contains("Nothing changed"))
    }

    // MARK: - #35 The day formatter is kept per time zone

    /// AppCalendar's zone (`autoupdatingCurrent`) follows the Mac's system
    /// zone, not the app's default zone, so a test can't move it; a change of
    /// zone with the app open is a device check. What can be checked: the
    /// MCP formatter is made for AppCalendar's zone, and a formatter made
    /// for a zone keeps it. The old one was a single formatter with no zone
    /// of its own, so it changed under every caller holding it, and whether
    /// it followed the Mac's zone was never certain.
    @Test("#35 MCPNotebookTools.isoDay is made for AppCalendar's zone, and each zone's formatter keeps it")
    func isoDayKeptPerZone() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        // 2026-10-17 03:00 UTC: the 17th in Tokyo, still the 16th in Los Angeles.
        let instant = Date(timeIntervalSince1970: 1_792_206_000)

        #expect(MCPNotebookTools.isoDay.timeZone.identifier == AppCalendar.shared.timeZone.identifier)

        let inTokyo = DateFormatters.isoDayPOSIX(in: tokyo)
        let inLosAngeles = DateFormatters.isoDayPOSIX(in: losAngeles)
        #expect(inTokyo !== inLosAngeles)
        #expect(inTokyo.timeZone.identifier == "Asia/Tokyo")
        #expect(inTokyo.string(from: instant) == "2026-10-17")
        #expect(inLosAngeles.timeZone.identifier == "America/Los_Angeles")
        #expect(inLosAngeles.string(from: instant) == "2026-10-16")
        // The same zone again reuses the last formatter.
        #expect(DateFormatters.isoDayPOSIX(in: losAngeles) === inLosAngeles)
    }
}
