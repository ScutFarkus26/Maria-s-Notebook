import Foundation
import CoreData
import OSLog

/// Generates AI-powered narrative summaries for student progress reports.
/// Uses the AnthropicAPIClient to produce structured narratives from student data.
enum AIReportService {
    struct MasteryBreakdown {
        let presented: Int
        let practicing: Int
        let readyForAssessment: Int
        let proficient: Int
        var total: Int { presented + practicing + readyForAssessment + proficient }
    }

}
