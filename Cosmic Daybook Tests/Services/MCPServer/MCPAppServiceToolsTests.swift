import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP App Service Tools")
@MainActor
struct MCPAppServiceToolsTests {
    private struct Harness {
        let tools: [MCPToolDefinition]
        let context: NSManagedObjectContext
        let dependencies: AppDependencies
    }

    private func makeHarness() throws -> Harness {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let dependencies = AppDependencies(coreDataStack: stack)
        let tools = MCPNotebookTools.makeTools(context: { context }, dependencies: { dependencies })
        return Harness(tools: tools, context: context, dependencies: dependencies)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    @discardableResult
    private func seedReport(
        in context: NSManagedObjectContext, student: CDStudent, month: String,
        body: String, status: MonthlyReportStatus
    ) throws -> CDParentCommunication {
        let report = CDParentCommunication(context: context)
        report.studentID = try #require(student.id).uuidString
        report.monthKey = month
        report.communicationType = .monthlyReport
        report.subject = "Report"
        report.body = body
        report.status = status
        return report
    }

    // MARK: - Registration

    @Test("both app-service tools are registered")
    func toolsAreRegistered() throws {
        let harness = try makeHarness()
        let names = Set(harness.tools.map(\.name))
        #expect(names.contains("create_backup"))
        #expect(names.contains("draft_parent_report"))
    }

    @Test("without a registered container the tools say the app is still starting")
    func toolsRefuseWithoutDependencies() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context }, dependencies: { nil })

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "create_backup", in: tools).handler([:])
        }
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "draft_parent_report", in: tools).handler(["student_name": .string("Ora")])
        }
    }

    // MARK: - create_backup

    @Test("create_backup writes an archive and reports its path")
    func createBackupWritesAnArchive() async throws {
        let harness = try makeHarness()
        CoreDataTestHelpers.seedStudent(in: harness.context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(harness.context)

        let output = try await tool(named: "create_backup", in: harness.tools).handler([:])
        #expect(output.hasPrefix("Backup written "))
        let marker = "[backup path="
        let start = try #require(output.range(of: marker)?.upperBound)
        let end = try #require(output[start...].firstIndex(of: "]"))
        let path = String(output[start..<end])
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(path.contains("ManualBackup-"))
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - draft_parent_report

    @Test("draft_parent_report reports a month with no evidence instead of filing an empty draft")
    func draftWithNoEvidenceWritesNothing() async throws {
        let harness = try makeHarness()
        let ora = CoreDataTestHelpers.seedStudent(in: harness.context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(harness.context)

        let output = try await tool(named: "draft_parent_report", in: harness.tools).handler([
            "student_name": .string("Ora"), "month": .string("2026-08")
        ])
        #expect(output.contains("No evidence was recorded for Ora Levi in August 2026"))
        let reports = harness.context.safeFetch(CDFetchRequest(CDParentCommunication.self))
        #expect(reports.isEmpty)
        #expect(ora.id != nil)
    }

    @Test("draft_parent_report refuses to touch a reviewed or sent report")
    func draftRefusesReviewedReport() async throws {
        let harness = try makeHarness()
        let ora = CoreDataTestHelpers.seedStudent(in: harness.context, firstName: "Ora", lastName: "Levi")
        try seedReport(in: harness.context, student: ora, month: "2026-08", body: "Sent already.", status: .sent)
        CoreDataTestHelpers.save(harness.context)

        do {
            _ = try await tool(named: "draft_parent_report", in: harness.tools).handler([
                "student_name": .string("Ora"), "month": .string("2026-08"), "overwrite": .bool(true)
            ])
            Issue.record("Expected the sent report to be protected")
        } catch let error as MCPToolError {
            #expect(error.message.contains("already sent"))
            #expect(error.message.contains("[communication id="))
        }
        let report = try #require(harness.context.safeFetch(CDFetchRequest(CDParentCommunication.self)).first)
        #expect(report.body == "Sent already.")
        #expect(report.status == .sent)
    }

    @Test("draft_parent_report keeps an existing draft's text unless overwrite is true")
    func draftKeepsExistingDraftWithoutOverwrite() async throws {
        let harness = try makeHarness()
        let ora = CoreDataTestHelpers.seedStudent(in: harness.context, firstName: "Ora", lastName: "Levi")
        try seedReport(in: harness.context, student: ora, month: "2026-08", body: "Guide's own words.", status: .draft)
        CoreDataTestHelpers.save(harness.context)

        let output = try await tool(named: "draft_parent_report", in: harness.tools).handler([
            "student_name": .string("Ora"), "month": .string("2026-08")
        ])
        #expect(output.contains("already has a draft"))
        #expect(output.contains("Pass overwrite: true"))
        let report = try #require(harness.context.safeFetch(CDFetchRequest(CDParentCommunication.self)).first)
        #expect(report.body == "Guide's own words.")
    }

    @Test("draft_parent_report rejects a malformed month")
    func draftRejectsBadMonth() async throws {
        let harness = try makeHarness()
        CoreDataTestHelpers.seedStudent(in: harness.context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(harness.context)

        do {
            _ = try await tool(named: "draft_parent_report", in: harness.tools).handler([
                "student_name": .string("Ora"), "month": .string("September")
            ])
            Issue.record("Expected the month to be rejected")
        } catch let error as MCPToolError {
            #expect(error.message.contains("YYYY-MM"))
        }
    }
}
