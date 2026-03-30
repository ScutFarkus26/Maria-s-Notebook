import Foundation
import SwiftData
import OSLog

/// Generates AI-powered narrative summaries for student progress reports.
/// Uses the AnthropicAPIClient to produce structured narratives from student data.
@MainActor
enum AIReportService {
    private static let logger = Logger.reports

    struct ReportData {
        let student: Student
        let notes: [Note]
        let attendanceRate: Double?
        let totalSchoolDays: Int
        let daysPresent: Int
        let masteryBreakdown: MasteryBreakdown?
        let lessonCount: Int
        let dateRange: ClosedRange<Date>
        let style: ReportGeneratorService.ReportStyle
    }

    struct MasteryBreakdown {
        let presented: Int
        let practicing: Int
        let readyForAssessment: Int
        let proficient: Int
        var total: Int { presented + practicing + readyForAssessment + proficient }
    }

    /// Generate an AI narrative summary for a student report.
    /// Returns nil if no API key is configured or the request fails.
    static func generateNarrative(from data: ReportData) async -> String? {
        guard AnthropicAPIClient.hasAPIKey() else {
            logger.info("AI report skipped: no API key configured")
            return nil
        }

        let client = AnthropicAPIClient()
        let prompt = buildPrompt(from: data)
        let systemMessage = """
            You are an experienced Montessori teacher writing a progress report. \
            Write in a warm, professional tone appropriate for \(data.style.audienceDescription). \
            Focus on growth, strengths, and concrete next steps. \
            Be specific when referencing observations. Keep the summary to 3-5 paragraphs.
            """

        do {
            let messages: [[String: String]] = [["role": "user", "content": prompt]]
            let response = try await client.sendConversation(
                messages: messages,
                systemMessage: systemMessage,
                temperature: 0.6,
                maxTokens: 1024
            )
            return response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch {
            logger.error("AI report generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Gather all report data from the model context for a student and date range.
    static func gatherReportData(
        student: Student,
        notes: [Note],
        dateRange: ClosedRange<Date>,
        style: ReportGeneratorService.ReportStyle,
        context: ModelContext
    ) -> ReportData {
        // Attendance
        let (daysPresent, totalDays, rate) = fetchAttendanceStats(
            studentID: student.id,
            dateRange: dateRange,
            context: context
        )

        // Mastery
        let mastery = fetchMasteryBreakdown(
            studentID: student.id,
            dateRange: dateRange,
            context: context
        )

        // Lesson count
        let lessonCount = fetchLessonPresentationCount(
            studentID: student.id,
            dateRange: dateRange,
            context: context
        )

        return ReportData(
            student: student,
            notes: notes,
            attendanceRate: rate,
            totalSchoolDays: totalDays,
            daysPresent: daysPresent,
            masteryBreakdown: mastery,
            lessonCount: lessonCount,
            dateRange: dateRange,
            style: style
        )
    }

    // MARK: - Private Helpers

    private static func buildPrompt(from data: ReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let startDate = dateFormatter.string(from: data.dateRange.lowerBound)
        let endDate = dateFormatter.string(from: data.dateRange.upperBound)

        var prompt = """
            Write a \(data.style.rawValue) for \(data.student.firstName) \(data.student.lastName) \
            covering the period \(startDate) to \(endDate).

            """

        // Attendance section
        if let rate = data.attendanceRate {
            let pct = Int(rate * 100)
            prompt += """

                ATTENDANCE: \(data.daysPresent) of \(data.totalSchoolDays) school days (\(pct)% attendance rate).
                """
        }

        // Mastery section
        if let mastery = data.masteryBreakdown, mastery.total > 0 {
            prompt += """

                CURRICULUM MASTERY:
                - Proficient/Mastered: \(mastery.proficient)
                - Practicing: \(mastery.practicing)
                - Presented: \(mastery.presented)
                - Ready for Assessment: \(mastery.readyForAssessment)
                - Total lessons tracked: \(mastery.total)
                """
        }

        if data.lessonCount > 0 {
            prompt += "\nLESSONS GIVEN: \(data.lessonCount) lessons presented during this period.\n"
        }

        // Notes section
        if !data.notes.isEmpty {
            prompt += "\nTEACHER OBSERVATIONS (\(data.notes.count) notes):\n"
            for note in data.notes.prefix(30) {
                let date = dateFormatter.string(from: note.createdAt)
                let tags = note.tags.map { TagHelper.tagName($0) }.joined(separator: ", ")
                let tagLabel = tags.isEmpty ? "" : " [\(tags)]"
                let body = String(note.body.prefix(300))
                prompt += "- \(date)\(tagLabel): \(body)\n"
            }
            if data.notes.count > 30 {
                prompt += "... and \(data.notes.count - 30) additional observations.\n"
            }
        }

        return prompt
    }

    private static func fetchAttendanceStats(
        studentID: UUID,
        dateRange: ClosedRange<Date>,
        context: ModelContext
    ) -> (daysPresent: Int, totalDays: Int, rate: Double?) {
        let studentIDStr = studentID.uuidString
        let startDate = dateRange.lowerBound
        let endDate = dateRange.upperBound

        let descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate<AttendanceRecord> {
                $0.studentID == studentIDStr &&
                $0.date >= startDate &&
                $0.date <= endDate
            }
        )
        let records = context.safeFetch(descriptor)
        guard !records.isEmpty else { return (0, 0, nil) }

        let present = records.filter { $0.status == .present || $0.status == .tardy }.count
        let total = records.count
        let rate = total > 0 ? Double(present) / Double(total) : nil
        return (present, total, rate)
    }

    private static func fetchMasteryBreakdown(
        studentID: UUID,
        dateRange: ClosedRange<Date>,
        context: ModelContext
    ) -> MasteryBreakdown? {
        let studentIDStr = studentID.uuidString
        let presentations = context.safeFetch(FetchDescriptor<LessonPresentation>())
            .filter { $0.studentID == studentIDStr }

        guard !presentations.isEmpty else { return nil }

        var presented = 0, practicing = 0, ready = 0, proficient = 0
        for p in presentations {
            switch p.state {
            case .presented: presented += 1
            case .practicing: practicing += 1
            case .readyForAssessment: ready += 1
            case .proficient: proficient += 1
            }
        }

        return MasteryBreakdown(
            presented: presented,
            practicing: practicing,
            readyForAssessment: ready,
            proficient: proficient
        )
    }

    private static func fetchLessonPresentationCount(
        studentID: UUID,
        dateRange: ClosedRange<Date>,
        context: ModelContext
    ) -> Int {
        let studentIDStr = studentID.uuidString
        let startDate = dateRange.lowerBound
        let endDate = dateRange.upperBound

        let descriptor = FetchDescriptor<LessonPresentation>(
            predicate: #Predicate<LessonPresentation> {
                $0.studentID == studentIDStr &&
                $0.presentedAt >= startDate &&
                $0.presentedAt <= endDate
            }
        )
        return context.safeFetch(descriptor).count
    }
}

// MARK: - ReportStyle Extension

extension ReportGeneratorService.ReportStyle {
    var audienceDescription: String {
        switch self {
        case .progressReport: return "a formal progress report shared with parents and administrators"
        case .parentConference: return "a parent-teacher conference discussion guide"
        case .iepDocumentation: return "IEP documentation requiring specific, measurable observations"
        }
    }
}
