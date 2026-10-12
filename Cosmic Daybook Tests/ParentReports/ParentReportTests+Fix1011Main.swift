import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Review 2026-10-11 (a), #2 and #5: a sent report stays what went home however
// many rows sync left for the month, and an untouched AI draft can be
// regenerated without asking.
/// Always fails; these tests never draft.
private struct NoModelClient: MCPClientProtocol {
    struct Offline: Error {}
    func generateText(prompt: String, temperature: Double) async throws -> String { throw Offline() }
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { throw Offline() }
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?
    ) async throws -> String { throw Offline() }
    // swiftlint:disable:next function_parameter_count
    func streamConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, timeout: TimeInterval?,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String { throw Offline() }
}

@Suite("Parent reports (review fixes 10-11)")
@MainActor
struct ParentReportReviewFix1011Tests {

    private let month = ReportMonth(year: 2026, month: 9)

    private func makeService(_ context: NSManagedObjectContext) -> MonthlyReportDraftService {
        MonthlyReportDraftService(
            modelContext: context,
            mcpClient: NoModelClient(),
            reportService: ReportGeneratorService()
        )
    }

    /// A report row as another device would have made it.
    @discardableResult
    private func seedReport(
        for studentID: String, status: MonthlyReportStatus, body: String, in context: NSManagedObjectContext
    ) -> CDParentCommunication {
        let report = CDParentCommunication(context: context)
        report.studentID = studentID
        report.monthKey = month.monthKey
        report.communicationTypeRaw = CommunicationType.monthlyReport.rawValue
        report.statusRaw = status.rawValue
        report.body = body
        return report
    }

    @Test("Two rows for one month: the sent one is the report, whichever comes back first")
    func existingReportPrefersSent() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let studentID = try #require(student.id).uuidString
        // The draft twin is made first, so an unsorted fetch returns it first.
        seedReport(for: studentID, status: .draft, body: "Draft twin.", in: context)
        let sent = seedReport(for: studentID, status: .sent, body: "What went home.", in: context)
        try context.save()
        let service = makeService(context)

        #expect(service.existingReport(studentID: studentID, monthKey: month.monthKey)?.objectID == sent.objectID)

        service.upsertReport(
            for: student, month: month,
            draft: .init(narrative: "A fresh draft.", aiGenerated: true, includedRefs: [])
        )
        #expect(sent.body == "What went home.")
        #expect(sent.status == .sent)
    }

    @Test("Typing never rewrites a sent report")
    func typingKeepsSentReport() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let sent = seedReport(
            for: try #require(student.id).uuidString, status: .sent, body: "What went home.", in: context
        )
        try context.save()

        _ = makeService(context).saveTypedNarrative("Changed afterward.", for: student, month: month)
        #expect(sent.body == "What went home.")
    }

    @Test("Typing into an AI draft makes it the guide's text")
    func typingClearsAIFlag() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let service = makeService(context)
        let report = service.upsertReport(
            for: student, month: month,
            draft: .init(narrative: "The draft.", aiGenerated: true, includedRefs: [])
        )
        #expect(report.aiGenerated)

        _ = service.saveTypedNarrative("The draft.", for: student, month: month)
        #expect(report.aiGenerated, "Unchanged text is still the draft")
        _ = service.saveTypedNarrative("The draft, edited.", for: student, month: month)
        #expect(!report.aiGenerated)
    }
}
