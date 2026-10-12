// MonthlyReportDraftService.swift
// Drafts, stores, and tracks monthly parent progress reports.
//
// Per Documentation/Architecture/AI.md: AI organizes and reflects; the guide
// decides. Drafts route through AIClientRouter (Apple Intelligence,
// on-device first), are labeled as AI-generated, and only ever land in an editable
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

        // Finished work only: Keep Practicing and Incomplete carry a "#" suffix.
        let completions = context.workEvidence.filter { $0.ref.hasPrefix("work:") && !$0.ref.contains("#") }
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
    ///
    /// A report already sent is what went home, and it is returned as it is:
    /// a new draft never replaces its text or puts it back to Draft (bug hunt
    /// 2026-10-11 #67). Callers check `status` when they need to know.
    @discardableResult
    func upsertReport(for student: CDStudent, month: ReportMonth, draft: Draft) -> CDParentCommunication {
        let studentID = student.id?.uuidString ?? ""
        let existing = existingReport(studentID: studentID, monthKey: month.monthKey)
        if let existing, existing.status == .sent {
            logger.notice("Kept a sent report; a new draft doesn't replace it")
            return existing
        }
        let report = existing ?? makeReport(studentID: studentID, month: month, studentName: student.shortName)

        report.body = draft.narrative
        report.aiGenerated = draft.aiGenerated
        report.includedRefs = draft.includedRefs
        report.statusRaw = MonthlyReportStatus.draft.rawValue
        report.modifiedAt = Date()
        modelContext.safeSave()
        return report
    }

    /// Drafts a report for each of `students` who has none for `month`, one at
    /// a time, and returns how many it drafted. `progress` hears (n, of)
    /// before each one.
    ///
    /// The month is a value, fixed for the whole run, and a child whose report
    /// exists by the time her turn comes, or appears while hers is drafting
    /// (written here, on another device, or through Claude), is skipped. The
    /// run used to read the screen's month after every draft and could write
    /// over another month's reports, sent ones included (2026-10-11 #67).
    @discardableResult
    func draftMissingReports(
        for students: [CDStudent],
        month: ReportMonth,
        progress: (Int, Int) -> Void = { _, _ in }
    ) async -> Int {
        var drafted = 0
        for (index, student) in students.enumerated() {
            progress(index + 1, students.count)
            let studentID = student.id?.uuidString ?? ""
            guard existingReport(studentID: studentID, monthKey: month.monthKey) == nil else { continue }
            let draft = await generateDraft(for: student, month: month, includeStudentReflection: false)
            guard existingReport(studentID: studentID, monthKey: month.monthKey) == nil else { continue }
            if !draft.narrative.isEmpty || !draft.includedRefs.isEmpty {
                upsertReport(for: student, month: month, draft: draft)
                drafted += 1
            }
        }
        return drafted
    }

    /// Puts what the guide typed into the (student, month) report, making the
    /// report when she types before any draft: her own words, a Draft, not
    /// AI-written. That text used to be dropped, and the report couldn't be
    /// sent (2026-10-11 #69). Returns the report, or nil when there is none
    /// and nothing was typed; the caller saves.
    @discardableResult
    func saveTypedNarrative(_ text: String, for student: CDStudent, month: ReportMonth) -> CDParentCommunication? {
        let studentID = student.id?.uuidString ?? ""
        if let report = existingReport(studentID: studentID, monthKey: month.monthKey) {
            // What went home stays as it went.
            guard report.status != .sent, report.body != text else { return report }
            report.body = text
            // Her words now, so Regenerate asks before replacing them.
            report.aiGenerated = false
            report.modifiedAt = Date()
            return report
        }
        guard !text.trimmed().isEmpty else { return nil }
        let report = makeReport(studentID: studentID, month: month, studentName: student.shortName)
        report.body = text
        report.aiGenerated = false
        report.includedRefs = []
        report.statusRaw = MonthlyReportStatus.draft.rawValue
        report.modifiedAt = Date()
        return report
    }

    /// Whether Regenerate should ask before replacing `current`, the report's
    /// text, with a new draft. `lastGenerated` is the draft this editor last
    /// produced, nil when it hasn't produced one.
    ///
    /// Any other text is the guide's (an edit, or words typed before any
    /// draft), so replacing it asks first; Regenerate used to throw it away
    /// with no warning (2026-10-11 #68). Empty text asks nothing.
    static func replacingNeedsConfirmation(current: String, lastGenerated: String?) -> Bool {
        let text = current.trimmed()
        guard !text.isEmpty else { return false }
        return text != lastGenerated?.trimmed()
    }

    /// The child's report for the month. Two rows (made on two devices before
    /// syncing) read as the one furthest along, as in `reports(for:)`, so a
    /// sent report is never taken for its draft twin and drafted over.
    func existingReport(studentID: String, monthKey: String) -> CDParentCommunication? {
        let request = CDParentCommunication.monthlyReportRequest(studentID: studentID, monthKey: monthKey)
        request.fetchLimit = 0
        return modelContext.safeFetch(request).max { Self.progress(of: $0) < Self.progress(of: $1) }
    }

    /// All monthly report rows for one cycle, keyed by studentID.
    func reports(for month: ReportMonth) -> [String: CDParentCommunication] {
        let request = CDFetchRequest(CDParentCommunication.self)
        request.predicate = NSPredicate(
            format: "monthKey == %@ AND communicationTypeRaw == %@",
            month.monthKey, CommunicationType.monthlyReport.rawValue
        )
        // Two rows for one child (made on two devices before syncing) read as
        // the one furthest along, so a sent report is never shown as a draft.
        var byStudent: [String: CDParentCommunication] = [:]
        for report in modelContext.safeFetch(request) {
            if let kept = byStudent[report.studentID], Self.progress(of: kept) >= Self.progress(of: report) {
                continue
            }
            byStudent[report.studentID] = report
        }
        return byStudent
    }

    private static func progress(of report: CDParentCommunication) -> Int {
        switch report.status {
        case .draft: return 0
        case .reviewed: return 1
        case .sent: return 2
        }
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
