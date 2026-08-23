// MonthlyReportDraftServiceTests.swift
// The draft service must always hand the guide an editable draft (deterministic
// fallback when no model is available), never duplicate a (student, month) row,
// and record sends faithfully.

import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

// MARK: - Stub AI clients

/// Always fails — drives the deterministic fallback path.
private struct UnavailableModelClient: MCPClientProtocol {
    struct Unavailable: Error {}
    func generateText(prompt: String, temperature: Double) async throws -> String { throw Unavailable() }
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { throw Unavailable() }
    func analyzePatterns(text: String, context: String) async throws -> [String] { throw Unavailable() }
    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult] { throw Unavailable() }
    // swiftlint:disable:next function_parameter_count
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, model: String?, timeout: TimeInterval?
    ) async throws -> String { throw Unavailable() }
    // swiftlint:disable:next function_parameter_count
    func streamConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, model: String?, timeout: TimeInterval?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String { throw Unavailable() }
}

/// Returns a fixed narrative — drives the AI path.
private struct FixedNarrativeClient: MCPClientProtocol {
    let narrative: String
    func generateText(prompt: String, temperature: Double) async throws -> String { narrative }
    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String { "{}" }
    func analyzePatterns(text: String, context: String) async throws -> [String] { [] }
    func searchKnowledgeBase(query: String, domain: String) async throws -> [KnowledgeBaseResult] { [] }
    // swiftlint:disable:next function_parameter_count
    func sendConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, model: String?, timeout: TimeInterval?
    ) async throws -> String { narrative }
    // swiftlint:disable:next function_parameter_count
    func streamConversation(
        messages: [[String: String]], systemMessage: String?, temperature: Double,
        maxTokens: Int, model: String?, timeout: TimeInterval?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String { narrative }
}

// MARK: - Tests

@Suite("Monthly Report Draft Service")
@MainActor
final class MonthlyReportDraftServiceTests {

    private let month = ReportMonth(year: 2026, month: 9)

    private func date(_ year: Int, _ monthValue: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = monthValue
        components.day = day
        components.hour = 10
        return Calendar.current.date(from: components)!
    }

    private func seedRecordedMonth(
        _ ctx: NSManagedObjectContext
    ) throws -> CDStudent {
        let student = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Miriam", lastName: "Vale", level: .upper)
        let studentID = try #require(student.id).uuidString

        let lesson = CDLesson(context: ctx)
        lesson.id = UUID()
        lesson.name = "Fraction Insets"

        let presentation = CDLessonPresentation(context: ctx)
        presentation.id = UUID()
        presentation.studentID = studentID
        presentation.lessonID = try #require(lesson.id).uuidString
        presentation.stateRaw = LessonPresentationState.presented.rawValue
        presentation.presentedAt = date(2026, 9, 2)

        #expect(CoreDataTestHelpers.save(ctx))
        return student
    }

    @Test("Model unavailable falls back to a deterministic, labeled draft")
    func fallbackDraft() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = try seedRecordedMonth(ctx)

        let service = MonthlyReportDraftService(
            modelContext: ctx,
            mcpClient: UnavailableModelClient(),
            reportService: ReportGeneratorService()
        )

        let draft = await service.generateDraft(for: student, month: month, includeStudentReflection: false)
        #expect(draft.aiGenerated == false)
        #expect(draft.narrative.contains("Fraction Insets"))
        #expect(!draft.includedRefs.isEmpty)

        // Deterministic: same inputs, same words.
        let second = await service.generateDraft(for: student, month: month, includeStudentReflection: false)
        #expect(second.narrative == draft.narrative)
    }

    @Test("AI path labels the draft and keeps evidence refs")
    func aiDraftLabeled() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = try seedRecordedMonth(ctx)

        let service = MonthlyReportDraftService(
            modelContext: ctx,
            mcpClient: FixedNarrativeClient(narrative: "  Miriam worked with the fraction insets.  "),
            reportService: ReportGeneratorService()
        )

        let draft = await service.generateDraft(for: student, month: month, includeStudentReflection: false)
        #expect(draft.aiGenerated == true)
        #expect(draft.narrative == "Miriam worked with the fraction insets.")
        #expect(!draft.includedRefs.isEmpty)
    }

    @Test("A month with no records produces an empty draft, not an invented one")
    func emptyMonthProducesEmptyDraft() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Ari", lastName: "Cedar", level: .upper)
        #expect(CoreDataTestHelpers.save(ctx))

        let service = MonthlyReportDraftService(
            modelContext: ctx,
            mcpClient: FixedNarrativeClient(narrative: "Should never be used"),
            reportService: ReportGeneratorService()
        )

        let draft = await service.generateDraft(for: student, month: month, includeStudentReflection: false)
        #expect(draft.narrative.isEmpty)
        #expect(draft.includedRefs.isEmpty)
        #expect(draft.aiGenerated == false)
    }

    @Test("Upsert never duplicates a (student, month) report row")
    func upsertIdempotence() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = try seedRecordedMonth(ctx)
        let studentID = try #require(student.id).uuidString

        let service = MonthlyReportDraftService(
            modelContext: ctx,
            mcpClient: UnavailableModelClient(),
            reportService: ReportGeneratorService()
        )

        let draft = await service.generateDraft(for: student, month: month, includeStudentReflection: false)
        let first = service.upsertReport(for: student, month: month, draft: draft)
        let second = service.upsertReport(for: student, month: month, draft: draft)
        #expect(first.objectID == second.objectID)

        let request = NSFetchRequest<CDParentCommunication>(entityName: "ParentCommunication")
        request.predicate = NSPredicate(format: "studentID == %@ AND monthKey == %@", studentID, month.monthKey)
        #expect(ctx.safeFetch(request).count == 1)

        // Regeneration resets review status back to draft.
        service.markReviewed(first)
        #expect(first.status == .reviewed)
        service.upsertReport(for: student, month: month, draft: draft)
        #expect(first.status == .draft)
    }

    @Test("markSent snapshots recipients and stamps sentAt")
    func markSentRecordsSend() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = try seedRecordedMonth(ctx)

        let service = MonthlyReportDraftService(
            modelContext: ctx,
            mcpClient: UnavailableModelClient(),
            reportService: ReportGeneratorService()
        )
        let draft = await service.generateDraft(for: student, month: month, includeStudentReflection: false)
        let report = service.upsertReport(for: student, month: month, draft: draft)

        service.markSent(report, recipients: ["family@example.com", "second@example.com"])
        #expect(report.status == .sent)
        #expect(report.sentAt != nil)
        #expect(report.recipientsSnapshot == "family@example.com, second@example.com")

        // The cycle map sees it.
        let byStudent = service.reports(for: month)
        #expect(byStudent[report.studentID]?.objectID == report.objectID)
    }
}
