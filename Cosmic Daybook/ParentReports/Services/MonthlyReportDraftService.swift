// MonthlyReportDraftService.swift
// Drafts, stores, and tracks monthly parent progress reports.
//
// Per Documentation/Architecture/AI.md: AI organizes and reflects; the guide
// decides. Drafts route through AIClientRouter (.backgroundTasks — on-device
// by default), are labeled as AI-generated, and only ever land in an editable
// CDParentCommunication draft. Nothing is sent without the guide's review.

import Foundation
import CoreData
import OSLog

@Observable
final class MonthlyReportDraftService {
    struct Draft: Sendable {
        let narrative: String
        let aiGenerated: Bool
        let includedRefs: [String]
    }

    private let modelContext: NSManagedObjectContext
    private let mcpClient: MCPClientProtocol
    private let contextBuilder: MonthlyReportContextBuilder
    private let logger = Logger.reports

    init(
        modelContext: NSManagedObjectContext,
        mcpClient: MCPClientProtocol,
        reportService: ReportGeneratorService
    ) {
        self.modelContext = modelContext
        self.mcpClient = mcpClient
        self.contextBuilder = MonthlyReportContextBuilder(
            context: modelContext,
            reportService: reportService
        )
    }

    // MARK: - Drafting

    /// Drafts a 3–6 sentence narrative from the month's recorded evidence.
    /// Falls back to a deterministic assembly when the model is unavailable —
    /// the caller always gets an editable draft, never an error.
    func generateDraft(
        for student: CDStudent,
        month: ReportMonth,
        includeStudentReflection: Bool
    ) async -> Draft {
        let reportContext = contextBuilder.buildContext(
            for: student,
            month: month,
            includeStudentReflection: includeStudentReflection
        )

        guard !reportContext.isEmpty else {
            return Draft(narrative: "", aiGenerated: false, includedRefs: [])
        }

        mcpClient.configureForFeature(.backgroundTasks)
        let systemMessage = AIPrompts.monthlyParentReportAssistant
        let prompt = Self.buildPrompt(from: reportContext, includeReflection: includeStudentReflection)

        do {
            let narrative = try await mcpClient.generateText(
                prompt: prompt,
                systemMessage: systemMessage,
                temperature: 0.6,
                maxTokens: 600
            )
            let trimmed = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return makeFallbackDraft(from: reportContext)
            }
            return Draft(narrative: trimmed, aiGenerated: true, includedRefs: reportContext.allRefs)
        } catch {
            logger.notice("Monthly report AI draft unavailable, using fallback: \(error.localizedDescription)")
            return makeFallbackDraft(from: reportContext)
        }
    }

    static func buildPrompt(from context: MonthlyReportContext, includeReflection: Bool) -> String {
        var lines: [String] = []
        lines.append(AIPrompts.monthlyParentReportInstructions(
            level: context.level,
            includeReflection: includeReflection
        ))
        lines.append("")
        lines.append("Child: \(context.studentName)")
        lines.append("Month: \(context.month.displayName)")
        lines.append("")
        lines.append("Recorded evidence (date — fact):")

        func appendSection(_ title: String, _ items: [MonthlyReportEvidenceItem]) {
            guard !items.isEmpty else { return }
            lines.append("")
            lines.append("\(title):")
            for item in items {
                let day = item.date.formatted(date: .abbreviated, time: .omitted)
                lines.append("- \(day) — \(item.phrase)")
            }
        }

        appendSection("Lessons presented", context.lessonsPresented)
        appendSection("Work", context.workEvidence)
        appendSection("Guide observations", context.observations)
        appendSection("Community contributions", context.contributions)
        appendSection("Student's own reflection", context.studentReflections)

        if let attendance = context.attendance {
            lines.append("")
            lines.append(
                "Attendance: present \(attendance.daysPresent) of "
                + "\(attendance.markedDays) marked school days."
            )
        }

        lines.append("")
        lines.append("Write the note now.")
        return lines.joined(separator: "\n")
    }

    /// Deterministic assembly from recorded evidence — used when no model is
    /// available. Same rules as the AI path: restate, never conclude.
    func makeFallbackDraft(from context: MonthlyReportContext) -> Draft {
        var sentences: [String] = []
        let firstName = context.studentName.components(separatedBy: " ").first ?? context.studentName

        let lessonPhrases = context.lessonsPresented
            .filter { $0.ref.hasSuffix("#proficient") == false && $0.ref.hasSuffix("#evidence") == false }
        if !lessonPhrases.isEmpty {
            let names = lessonPhrases.prefix(3).map { phrase in
                phrase.phrase.replacingOccurrences(of: "Received the lesson ", with: "")
            }
            let lessonList = names.joined(separator: ", ")
            let more = lessonPhrases.count > 3 ? " and others" : ""
            sentences.append("This month \(firstName) received \(lessonList)\(more).")
        }

        let completions = context.workEvidence.filter { $0.ref.hasPrefix("work:") }
        if !completions.isEmpty {
            let count = completions.count
            let workWord = count == 1 ? "a piece of follow-up work" : "\(count) pieces of follow-up work"
            sentences.append("\(firstName) completed \(workWord).")
        }

        if let observation = context.observations.last {
            sentences.append("From the guide's notebook: \(observation.phrase)")
        }

        if let contribution = context.contributions.last {
            let phrase = contribution.phrase.prefix(1).lowercased() + contribution.phrase.dropFirst()
            sentences.append("In the community, \(firstName) \(phrase).")
        }

        if let reflection = context.studentReflections.last {
            sentences.append(reflection.phrase + ".")
        }

        if let attendance = context.attendance {
            sentences.append(
                "\(firstName) was present \(attendance.daysPresent) of "
                + "\(attendance.markedDays) marked school days."
            )
        }

        return Draft(
            narrative: sentences.joined(separator: " "),
            aiGenerated: false,
            includedRefs: context.allRefs
        )
    }

    // MARK: - Persistence

    /// Fetch-or-create the report row for (student, month) — never duplicates.
    @discardableResult
    func upsertReport(for student: CDStudent, month: ReportMonth, draft: Draft) -> CDParentCommunication {
        let studentID = student.id?.uuidString ?? ""
        let report = existingReport(studentID: studentID, monthKey: month.monthKey)
            ?? makeReport(studentID: studentID, month: month, studentName: StudentFormatter.displayName(for: student))

        report.body = draft.narrative
        report.aiGenerated = draft.aiGenerated
        report.includedRefs = draft.includedRefs
        report.statusRaw = MonthlyReportStatus.draft.rawValue
        report.modifiedAt = Date()
        modelContext.safeSave()
        return report
    }

    func existingReport(studentID: String, monthKey: String) -> CDParentCommunication? {
        modelContext.safeFetchFirst(
            CDParentCommunication.monthlyReportRequest(studentID: studentID, monthKey: monthKey)
        )
    }

    /// All monthly report rows for one cycle, keyed by studentID.
    func reports(for month: ReportMonth) -> [String: CDParentCommunication] {
        let request = CDFetchRequest(CDParentCommunication.self)
        request.predicate = NSPredicate(
            format: "monthKey == %@ AND communicationTypeRaw == %@",
            month.monthKey, CommunicationType.monthlyReport.rawValue
        )
        var byStudent: [String: CDParentCommunication] = [:]
        for report in modelContext.safeFetch(request) {
            byStudent[report.studentID] = report
        }
        return byStudent
    }

    func markReviewed(_ report: CDParentCommunication) {
        report.statusRaw = MonthlyReportStatus.reviewed.rawValue
        report.modifiedAt = Date()
        modelContext.safeSave()
    }

    func markSent(_ report: CDParentCommunication, recipients: [String]) {
        report.statusRaw = MonthlyReportStatus.sent.rawValue
        report.recipientsSnapshot = recipients.joined(separator: ", ")
        report.sentAt = Date()
        report.modifiedAt = Date()
        modelContext.safeSave()
    }

    private func makeReport(studentID: String, month: ReportMonth, studentName: String) -> CDParentCommunication {
        let report = CDParentCommunication(context: modelContext)
        report.studentID = studentID
        report.monthKey = month.monthKey
        report.communicationType = .monthlyReport
        report.templateName = "Monthly Progress Report"
        report.subject = "\(studentName) — \(month.displayName) update"
        return report
    }
}
