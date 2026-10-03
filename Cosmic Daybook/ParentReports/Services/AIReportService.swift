import Foundation
import CoreData
import OSLog

/// Generates AI-powered narrative summaries for student progress reports.
/// Shared types for the narrative sections of student progress reports.
enum AIReportService {
    struct MasteryBreakdown {
        let presented: Int
        let practicing: Int
        let readyForAssessment: Int
        let proficient: Int
        var total: Int { presented + practicing + readyForAssessment + proficient }
    }

}
