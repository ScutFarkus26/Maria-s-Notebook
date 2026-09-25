import Foundation
import CoreData

// MARK: - AI Services

extension AppDependencies {

    /// The AI client router that keeps automatic requests within Apple Intelligence.
    /// All AI services should use this (via `mcpClient`) for inference.
    var aiRouter: AIClientRouter { _aiRouter }

    /// Protocol-typed client for injection into services.
    /// Points to the router, which handles Apple on-device and Private Cloud routing.
    var mcpClient: MCPClientProtocol {
        aiRouter
    }

    var studentAnalysisService: StudentAnalysisService { _studentAnalysisService }

    var reportGeneratorService: ReportGeneratorService { _reportGeneratorService }

    var monthlyReportDraftService: MonthlyReportDraftService { _monthlyReportDraftService }

    var meetingInsightsService: MeetingInsightsService { _meetingInsightsService }
}
