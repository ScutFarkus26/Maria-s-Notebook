import Foundation
import CoreData
import OSLog

/// ViewModel for the AI lesson planning assistant UI.
/// Manages planning session state, message history, recommendation actions,
/// and bridges between the view layer and LessonPlanningService.
@Observable
final class LessonPlanningViewModel {
    private static let logger = Logger.ai

    // MARK: - State

    var messages: [PlanningMessage] = []
    var recommendations: [LessonRecommendation] = []
    var isLoading = false
    var currentStep: PipelineStep = .idle
    var selectedDepth: PlanningDepth = .standard
    var errorMessage: String?

    let mode: PlanningMode

    private(set) var currentSession: PlanningSession?
    private var planningService: LessonPlanningService?
    private var managedObjectContext: NSManagedObjectContext?
    
    // MARK: - Computed

    var modeTitle: String {
        switch mode {
        case .singleStudent: return "Student Plan"
        }
    }
    
    var canApplyPlan: Bool {
        !recommendations.isEmpty && recommendations.contains { $0.decision == .accepted }
    }
    
    var acceptedRecommendations: [LessonRecommendation] {
        recommendations.filter { $0.decision == .accepted }
    }
    
    // MARK: - Init
    
    init(mode: PlanningMode) {
        self.mode = mode
        
        // Read saved default depth, fallback to standard
        let savedDepth = UserDefaults.standard.string(forKey: UserDefaultsKeys.lessonPlanningDefaultDepth)
            .flatMap { PlanningDepth(rawValue: $0) }
        selectedDepth = savedDepth?.effective ?? .standard
    }
    
    /// Configure with dependencies (called from view's onAppear)
    func configure(context: NSManagedObjectContext, mcpClient: MCPClientProtocol) {
        self.managedObjectContext = context
        self.planningService = LessonPlanningService(context: context, mcpClient: mcpClient)
    }

    // MARK: - Actions
    
    /// Starts the planning pipeline.
    func startPlanning() {
        guard let service = planningService, let context = managedObjectContext else {
            errorMessage = "Lesson planning isn't ready yet. Close this and try again."
            return
        }
        
        isLoading = true
        errorMessage = nil
        currentStep = .gatheringData
        
        Task {
            do {
                switch mode {
                case .singleStudent(let studentID):
                    try await planForStudent(studentID, service: service, context: context)
                }
            } catch {
                Self.logger.warning("Planning failed: \(error)")
                // Shown once, in the error banner.
                errorMessage = AppErrorMessages.aiMessage(
                    for: error, fallback: "Couldn't make a plan. Try again in a moment."
                )
                currentStep = .idle
            }
            isLoading = false
        }
    }
    
    /// Sends a follow-up message in the conversation.
    func sendMessage(_ text: String) {
        guard !text.trimmed().isEmpty,
              var session = currentSession,
              let service = planningService else { return }
        
        let trimmed = text.trimmed()
        messages.append(PlanningMessage(role: .teacher, content: trimmed))
        
        isLoading = true
        currentStep = .respondingToQuestion
        
        Task {
            do {
                let newRecs = try await service.respondToQuestion(trimmed, inSession: &session)
                self.currentSession = session
                
                if !newRecs.isEmpty {
                    self.recommendations = newRecs
                }
                
                // Sync messages from session
                self.messages = session.messages
                currentStep = .presentingPlan
            } catch {
                Self.logger.warning("Follow-up failed: \(error)")
                messages.append(PlanningMessage(
                    role: .system,
                    content: AppErrorMessages.aiMessage(
                        for: error, fallback: "Couldn't answer that. Try again in a moment."
                    )
                ))
                currentStep = .awaitingInput
            }
            isLoading = false
        }
    }
    
    /// Accepts a recommendation.
    func acceptRecommendation(_ id: UUID) {
        guard let index = recommendations.firstIndex(where: { $0.id == id }) else { return }
        recommendations[index].decision = .accepted

        if let session = currentSession, let context = managedObjectContext {
            PlanningFeedbackTracker.recordDecision(
                recommendation: recommendations[index],
                decision: .accepted,
                session: session,
                context: context
            )
        }
    }

    /// Rejects a recommendation.
    func rejectRecommendation(_ id: UUID) {
        guard let index = recommendations.firstIndex(where: { $0.id == id }) else { return }
        recommendations[index].decision = .rejected

        if let session = currentSession, let context = managedObjectContext {
            PlanningFeedbackTracker.recordDecision(
                recommendation: recommendations[index],
                decision: .rejected,
                session: session,
                context: context
            )
        }
    }
    
    /// Applies all accepted recommendations by creating CDLessonAssignment drafts.
    func applyPlan() {
        guard let service = planningService else { return }
        
        let toApply = acceptedRecommendations
        guard !toApply.isEmpty else { return }
        
        isLoading = true
        currentStep = .creatingAssignments
        
        do {
            let created = try service.applyRecommendations(toApply)
            
            messages.append(PlanningMessage(
                role: .assistant,
                content: "Added \(created.count) \(created.count == 1 ? "lesson" : "lessons") to the plan."
            ))
            
            currentStep = .complete
        } catch {
            Self.logger.warning("Failed to apply plan: \(error)")
            // Not an Apple Intelligence failure: the lessons didn't go into the plan.
            errorMessage = "Couldn't add these lessons to your plan. Try again."
            currentStep = .presentingPlan
        }
        
        isLoading = false
    }
    
    // MARK: - Private Pipeline Methods
    
    private func planForStudent(
        _ studentID: UUID,
        service: LessonPlanningService,
        context: NSManagedObjectContext
    ) async throws {
        let students = fetchStudents(context: context)
        guard let student = students.first(where: { $0.id == studentID }) else {
            throw PlanningError.studentNotFound
        }
        
        currentStep = .gatheringEvidence
        messages.append(PlanningMessage(
            role: .system,
            content: "Looking over \(student.firstName)'s lessons and notes…"
        ))
        
        currentStep = .generatingPlan
        
        let (recs, session) = try await service.suggestNextLessons(
            for: student,
            depth: selectedDepth
        )
        
        self.currentSession = session
        self.recommendations = recs
        self.messages = session.messages
        self.currentStep = .presentingPlan
    }
    
    /// The visible roster by last name only (no first-name tiebreak).
    private func fetchStudents(context: NSManagedObjectContext) -> [CDStudent] {
        DataQueryService(context: context).fetchAllStudents(
            excludeTest: true, excludeWithdrawn: true,
            sortBy: [NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)]
        )
    }
}

// MARK: - Planning Errors

enum PlanningError: Error, LocalizedError {
    case studentNotFound
    
    var errorDescription: String? {
        switch self {
        case .studentNotFound: return "Couldn't find this student. Close this and open it again."
        }
    }
}
