import Foundation
import CoreData

// MARK: - AI Services

extension AppDependencies {

    /// The AI client router that handles local-first routing with Claude fallback.
    /// All AI services should use this (via `mcpClient`) for inference.
    var aiRouter: AIClientRouter {
        if let router = _aiRouter { return router }
        let router = AIClientRouter()
        _aiRouter = router
        return router
    }

    /// Protocol-typed client for injection into services.
    /// Points to the router, which handles local/Claude routing transparently.
    var mcpClient: MCPClientProtocol {
        aiRouter
    }

    var chatService: ChatService {
        if let service = _chatService {
            return service
        }
        let service = ChatService(modelContext: viewContext, mcpClient: mcpClient)
        _chatService = service
        return service
    }

    var studentAnalysisService: StudentAnalysisService {
        if let service = _studentAnalysisService {
            return service
        }
        let service = StudentAnalysisService(
            modelContext: viewContext,
            mcpClient: mcpClient
        )
        _studentAnalysisService = service
        return service
    }

    var lessonPlanningService: LessonPlanningService {
        if let service = _lessonPlanningService {
            return service
        }
        let service = LessonPlanningService(
            context: viewContext,
            mcpClient: mcpClient
        )
        _lessonPlanningService = service
        return service
    }

    var databaseAnalysisService: DatabaseAnalysisService {
        if let service = _databaseAnalysisService { return service }
        let service = DatabaseAnalysisService(modelContext: viewContext, mcpClient: mcpClient)
        _databaseAnalysisService = service
        return service
    }

    var reportGeneratorService: ReportGeneratorService {
        if let service = _reportGeneratorService {
            return service
        }
        let service = ReportGeneratorService()
        _reportGeneratorService = service
        return service
    }

    var meetingInsightsService: MeetingInsightsService {
        if let service = _meetingInsightsService {
            return service
        }
        let service = MeetingInsightsService(
            modelContext: viewContext,
            mcpClient: mcpClient
        )
        _meetingInsightsService = service
        return service
    }
}
