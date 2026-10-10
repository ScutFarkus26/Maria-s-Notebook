import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, P1 #18 and #19: update_work's check-in replies say
/// what each row really has. A refusal names the call's status only when the
/// call logged it on this row, and a this-child-only add or move reads each
/// linked copy instead of assuming all of them match.
@Suite("MCP Work Check-In Replies (fix 10-10 C)")
@MainActor
struct MCPWorkCheckInRepliesFix1010CTests {
    private typealias Fixture = CheckInFixture

    @Test("a closed row refused an add names its own status, not one the call set for another child")
    func refusalNamesTheRowsOwnStatus() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])
        let eli = try #require(rows["Eli"])
        let update = try Fixture.tool(named: "update_work", in: tools)
        _ = try await update.handler([
            "work_id": .string(try Fixture.id(of: maya)),
            "status": .string("mastered"),
            "students": .array([.string("Maya Test")])
        ])
        #expect(maya.isClosed)
        #expect(!eli.isClosed)

        let refusal = await Fixture.message {
            try await update.handler([
                "work_id": .string(try Fixture.id(of: maya)),
                "status": .string("review"),
                "students": .array([.string("Eli Test")]),
                "add_check_in_on": .string("2026-09-24")
            ])
        }
        #expect(refusal.contains("already closed (Mastered)"))
        #expect(!refusal.contains("This call sets"))
        #expect(eli.status == .active)
        #expect(Fixture.checkIns(of: maya, on: "2026-09-24", in: context).isEmpty)
    }

    @Test("closing this row and adding in one call still says the call closed it")
    func refusalForThisCallsOwnStatusStays() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])

        let refusal = await Fixture.message {
            try await Fixture.tool(named: "update_work", in: tools).handler([
                "work_id": .string(try Fixture.id(of: maya)),
                "status": .string("mastered"),
                "students": .array([.string("Maya Test")]),
                "add_check_in_on": .string("2026-09-24")
            ])
        }
        #expect(refusal.contains("This call sets the work to Mastered"))
        #expect(!maya.isClosed)
    }

    @Test("a this-child-only add names the copy that already has a check-in that day")
    func thisChildOnlyAddReadsEachCopy() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli", "Ana"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])
        let eli = try #require(rows["Eli"])
        let update = try Fixture.tool(named: "update_work", in: tools)
        _ = try await update.handler([
            "work_id": .string(try Fixture.id(of: eli)),
            "add_check_in_on": .string("2026-09-24"),
            "add_check_in_for_this_child_only": .bool(true)
        ])

        let receipt = try await update.handler([
            "work_id": .string(try Fixture.id(of: maya)),
            "add_check_in_on": .string("2026-09-24"),
            "add_check_in_for_this_child_only": .bool(true)
        ])
        #expect(receipt.contains("this child only — 1 linked copy got no check-in on 2026-09-24"))
        #expect(receipt.contains(
            "Eli Test's linked copy [work id=\(try Fixture.id(of: eli))] already has a scheduled check-in on "
                + "2026-09-24"
        ))
        #expect(!receipt.contains("2 linked copies"))
    }

    @Test("a this-child-only move names a copy whose check-in is done and one that has none")
    func thisChildOnlyMoveReadsEachCopy() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli", "Ana"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])
        let eli = try #require(rows["Eli"])
        let ana = try #require(rows["Ana"])
        let update = try Fixture.tool(named: "update_work", in: tools)
        _ = try await update.handler([
            "work_id": .string(try Fixture.id(of: eli)),
            "complete_check_in_on": .string("2026-09-18")
        ])
        _ = try await update.handler([
            "work_id": .string(try Fixture.id(of: ana)),
            "move_check_in_from": .string("2026-09-18"),
            "move_check_in_to": .string("2026-09-21"),
            "move_check_in_for_this_child_only": .bool(true)
        ])

        let receipt = try await update.handler([
            "work_id": .string(try Fixture.id(of: maya)),
            "move_check_in_from": .string("2026-09-18"),
            "move_check_in_to": .string("2026-09-22"),
            "move_check_in_for_this_child_only": .bool(true)
        ])
        #expect(receipt.contains("moved the check-in from 2026-09-18 to 2026-09-22"))
        #expect(receipt.contains("this child only — the linked copies were left alone"))
        #expect(receipt.contains(
            "Eli Test's linked copy [work id=\(try Fixture.id(of: eli))] stayed on 2026-09-18 — "
                + "its check-in is already completed"
        ))
        #expect(receipt.contains(
            "Ana Test's linked copy [work id=\(try Fixture.id(of: ana))] has no check-in on 2026-09-18"
        ))
        #expect(!receipt.contains("still have their check-in"))
    }
}
