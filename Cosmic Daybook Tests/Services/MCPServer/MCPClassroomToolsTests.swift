import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Classroom Tools")
@MainActor
struct MCPClassroomToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    // MARK: - Supplies

    @Test("adjust_supply logs a transaction alongside the new count")
    func adjustSupplyWritesTransaction() async throws {
        let (tools, context) = try makeTools()
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = "Golden Beads"
        supply.categoryRaw = "Math"
        supply.currentQuantity = 20
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "adjust_supply", in: tools).handler([
            "supply": .string("Golden Beads"),
            "change": .int(-8),
            "reason": .string("Used in a lesson")
        ])
        #expect(receipt.contains("now 12"))
        #expect(supply.currentQuantity == 12)

        let transactions = context.safeFetch(CDFetchRequest(CDSupplyTransaction.self))
        #expect(transactions.count == 1)
        #expect(transactions.first?.quantityChange == -8)
    }

    @Test("adjust_supply refuses to drive stock negative")
    func adjustSupplyRefusesNegativeStock() async throws {
        let (tools, context) = try makeTools()
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = "Pencils"
        supply.categoryRaw = "Office"
        supply.currentQuantity = 3
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "adjust_supply", in: tools).handler([
                "supply": .string("Pencils"),
                "change": .int(-10)
            ])
        }
        #expect(supply.currentQuantity == 3)
    }

    @Test("adjust_supply set_to computes the difference from the counted total")
    func adjustSupplySetToComputesDelta() async throws {
        let (tools, context) = try makeTools()
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = "Sandpaper Letters"
        supply.categoryRaw = "Language"
        supply.currentQuantity = 10
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "adjust_supply", in: tools).handler([
            "supply": .string("Sandpaper Letters"),
            "set_to": .int(14),
            "reason": .string("Recounted")
        ])
        #expect(supply.currentQuantity == 14)
        let transaction = try #require(context.safeFetch(CDFetchRequest(CDSupplyTransaction.self)).first)
        #expect(transaction.quantityChange == 4)
    }

    // MARK: - Classroom Jobs

    @Test("assign_job rosters a student on the week's Monday")
    func assignJobKeysToMonday() async throws {
        let (tools, context) = try makeTools()
        let job = CDClassroomJob(context: context)
        job.id = UUID()
        job.name = "Plant Care"
        job.isActive = true
        job.maxStudents = 1
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Tess", lastName: "Oyelaran")
        CoreDataTestHelpers.save(context)

        // 2026-09-16 is a Wednesday; the roster week starts Monday the 14th.
        _ = try await tool(named: "assign_job", in: tools).handler([
            "job": .string("Plant Care"),
            "student_name": .string("Tess"),
            "week_of": .string("2026-09-16")
        ])

        let assignment = try #require(context.safeFetch(CDFetchRequest(CDJobAssignment.self)).first)
        let expected = try #require(MCPNotebookTools.isoDay.date(from: "2026-09-14"))
        #expect(assignment.weekStartDate == AppCalendar.startOfDay(expected))

        let roster = try await tool(named: "classroom_jobs", in: tools).handler([
            "week_of": .string("2026-09-14")
        ])
        #expect(roster.contains("Plant Care: Tess Oyelaran"))
    }

    @Test("assign_job honours a job's student limit")
    func assignJobHonoursLimit() async throws {
        let (tools, context) = try makeTools()
        let job = CDClassroomJob(context: context)
        job.id = UUID()
        job.name = "Line Leader"
        job.isActive = true
        job.maxStudents = 1
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ivy", lastName: "Chen")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Jon", lastName: "Alvarez")
        CoreDataTestHelpers.save(context)

        let assignTool = try tool(named: "assign_job", in: tools)
        _ = try await assignTool.handler([
            "job": .string("Line Leader"),
            "student_name": .string("Ivy"),
            "week_of": .string("2026-09-14")
        ])
        await #expect(throws: MCPToolError.self) {
            _ = try await assignTool.handler([
                "job": .string("Line Leader"),
                "student_name": .string("Jon"),
                "week_of": .string("2026-09-14")
            ])
        }
    }

    // MARK: - Issues

    @Test("update_issue stamps the resolution date when it is resolved")
    func updateIssueStampsResolution() async throws {
        let (tools, context) = try makeTools()
        let raised = try await tool(named: "update_issue", in: tools).handler([
            "title": .string("Loose shelf bracket"),
            "category": .string("Facility"),
            "priority": .string("High")
        ])
        #expect(raised.contains("Raised"))

        let issue = try #require(context.safeFetch(CDFetchRequest(CDIssue.self)).first)
        #expect(issue.resolvedAt == nil)
        let id = try #require(issue.id).uuidString

        _ = try await tool(named: "update_issue", in: tools).handler([
            "issue_id": .string(id),
            "status": .string("Resolved"),
            "resolution": .string("Re-anchored the bracket")
        ])
        #expect(issue.status == .resolved)
        #expect(issue.resolvedAt != nil)
    }

    @Test("list_issues hides settled issues unless a status is asked for")
    func listIssuesHidesSettledByDefault() async throws {
        let (tools, context) = try makeTools()
        let issue = CDIssue(context: context)
        issue.id = UUID()
        issue.title = "Old spill"
        issue.status = .closed
        issue.priority = .low
        issue.category = .facility
        CoreDataTestHelpers.save(context)

        let byDefault = try await tool(named: "list_issues", in: tools).handler([:])
        #expect(byDefault.contains("No issues are open."))

        let asked = try await tool(named: "list_issues", in: tools).handler([
            "status": .string("Closed")
        ])
        #expect(asked.contains("Old spill"))
    }
}
