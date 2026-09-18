import Foundation
import CoreData
import OSLog

/// Generates AI-powered narrative summaries for student progress reports.
/// Uses the AnthropicAPIClient to produce structured narratives from student data.
enum AIReportService {
    private static let logger = Logger.reports

    struct ReportData {
        let studentFirstName: String
        let studentLastName: String
        let notes: [NoteData]
        let attendanceRate: Double?
        let totalSchoolDays: Int
        let daysPresent: Int
        let masteryBreakdown: MasteryBreakdown?
        let lessonCount: Int
        let dateRange: ClosedRange<Date>
        let style: ReportGeneratorService.ReportStyle

        struct NoteData {
            let body: String
            let tags: [String]
            let createdAt: Date
        }
    }

    struct MasteryBreakdown {
        let presented: Int
        let practicing: Int
        let readyForAssessment: Int
        let proficient: Int
        var total: Int { presented + practicing + readyForAssessment + proficient }
    }

    // MARK: - Private Helpers

    private static func buildPrompt(from data: ReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let startDate = dateFormatter.string(from: data.dateRange.lowerBound)
        let endDate = dateFormatter.string(from: data.dateRange.upperBound)

        var prompt = """
            Write a \(data.style.rawValue) for \(data.studentFirstName) \(data.studentLastName) \
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

}
