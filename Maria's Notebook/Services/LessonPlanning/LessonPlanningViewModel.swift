import Foundation
import CoreData
import OSLog

/// ViewModel for the AI lesson planning assistant UI.
/// Manages planning session state, message history, recommendation actions,
/// and bridges between the view layer and LessonPlanningService.
@Observable
@MainActor
final class LessonPlanningViewModel {
    private static let logger = Logger.ai

    // MARK: - State

    var messages: [PlanningMessage] = []
    var recommendations: [LessonRecommendation] = []
    var weekPlan: WeekPlan?
    var isLoading = false
    var currentStep: PipelineStep = .idle
    var selectedDepth: PlanningDepth = .standard
    var errorMessage: String?

    let mode: PlanningMode

    private(set) var currentSession: PlanningSession?
    private var planningService: LessonPlanningService?
    private var managedObjectContext: NSManagedObjectContext?
    
    // MARK: - Computed
    
    var estimatedCost: String {
        let tokens = currentSession?.tokensUsed ?? 0
        if tokens == 0 { return "" }
        // Rough cost estimate: $3/M input + $15/M output for Claude Sonnet
        let cost = Double(tokens) * 0.003 / 1000.0 + Double(tokens) * 0.5 * 0.015 / 1000.0
        return String(format: "$%.3f", cost)
    }
    
    var modeTitle: String {
        switch mode {
        case .singleStudent: return "Student Plan"
        case .wholeClass: return "Class Plan"
        case .quickSuggest: return "Quick Suggest"
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
        
        // Read saved default depth, fallback to mode-appropriate default
        let savedDepth = UserDefaults.standard.string(forKey: UserDefaultsKeys.lessonPlanningDefaultDepth)
            .flatMap { PlanningDepth(rawValue: $0) }
        
        switch mode {
        case .quickSuggest:
            selectedDepth = .quick
        case .singleStudent:
            selectedDepth = savedDepth ?? .standard
        case .wholeClass:
            selectedDepth = savedDepth ?? .deep
        }
    }
    
    /// Configure with dependencies (called from view's onAppear)
    func configure(context: NSManagedObjectContext, mcpClient: MCPClientProtocol) {
        self.managedObjectContext = context
        self.planningService = LessonPlanningService(context: context, mcpClient: mcpClient)
    }

    /// Configure with dependencies (called from view's onAppear)
    @available(*, deprecated, message: "Use Core Data overload")
    func configure(modelContext: NSManagedObjectContext, mcpClient: MCPClientProtocol) {
        let coreDataContext = MainActor.assumeIsolated { AppBootstrapping.getSharedCoreDataStack().viewContext }
        self.configure(context: coreDataContext, mcpClient: mcpClient)
    }
    
    // MARK: - Actions
    
    /// Starts the planning pipeline.
    func startPlanning() {
        guard let service = planningService, let context = managedObjectContext else {
            errorMessage = "Service not configured"
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
                case .wholeClass:
                    try await planForClass(service: service, context: context)
                case .quickSuggest(let studentIDs):
                    try await quickSuggest(studentIDs, service: service, context: context)
                }
            } catch {
                Self.logger.warning("Planning failed: \(error)")
                errorMessage = error.localizedDescription
                messages.append(PlanningMessage(role: .system, content: "Error: \(error.localizedDescription)"))
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
                messages.append(PlanningMessage(role: .system, content: "Error: \(error.localizedDescription)"))
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
    
    /// Applies all accepted recommendations by creating LessonAssignment drafts.
    func applyPlan() {
        guard let service = planningService else { return }
        
        let toApply = acceptedRecommendations
        guard !toApply.isEmpty else { return }
        
        isLoading = true
        currentStep = .creatingAssignments
        
        // Build scheduled dates map from week plan
        var scheduledDates: [UUID: Date] = [:]
        if let plan = weekPlan {
            for day in plan.days {
                for rec in day.recommendations where toApply.contains(where: { $0.id == rec.id }) {
                    scheduledDates[rec.id] = day.date
                }
            }
        }
        
        do {
            let created = try service.applyRecommendations(toApply, scheduledDates: scheduledDates)
            
            messages.append(PlanningMessage(
                role: .assistant,
                content: "Created \(created.count) lesson assignment\(created.count == 1 ? "" : "s")."
            ))
            
            currentStep = .complete
        } catch {
            Self.logger.warning("Failed to apply plan: \(error)")
            errorMessage = error.localizedDescription
            currentStep = .presentingPlan
        }
        
        isLoading = false
    }
    
    /// Resets the planning session.
    func reset() {
        messages = []
        recommendations = []
        weekPlan = nil
        currentSession = nil
        currentStep = .idle
        errorMessage = nil
        isLoading = false
    }
    
    // MARK: - Private Pipeline Methods
    
    private func planForStudent(_ studentID: UUID, service: LessonPlanningService, context: NSManagedObjectContext) async throws {
        let students = fetchStudents(context: context)
        guard let student = students.first(where: { $0.id == studentID }) else {
            throw PlanningError.studentNotFound
        }
        
        currentStep = .assessingReadiness
        messages.append(PlanningMessage(role: .system, content: "Assessing readiness for \(student.fullName)..."))
        
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
    
    private func planForClass(service: LessonPlanningService, context: NSManagedObjectContext) async throws {
        let students = fetchStudents(context: context)
        guard !students.isEmpty else {
            throw PlanningError.noStudents
        }
        
        currentStep = .assessingReadiness
        messages.append(PlanningMessage(
            role: .system,
            content: "Assessing readiness for \(students.count) students..."
        ))
        
        currentStep = .generatingPlan
        
        let (plan, session) = try await service.generateWeekPlan(students: students)
        
        self.currentSession = session
        self.weekPlan = plan
        self.recommendations = session.recommendations
        self.messages = session.messages
        self.currentStep = .presentingPlan
    }
    
    private func quickSuggest(
        _ studentIDs: [UUID],
        service: LessonPlanningService,
        context: NSManagedObjectContext
    ) async throws {
        let students = fetchStudents(context: context)
        let filtered = students.filter { student in
            guard let id = student.id else { return false }
            return studentIDs.contains(id)
        }
        guard !filtered.isEmpty else {
            throw PlanningError.noStudents
        }
        
        currentStep = .assessingReadiness
        
        // Quick mode: run individual quick plans and merge results
        var allRecs: [LessonRecommendation] = []
        var latestSession: PlanningSession?
        
        for student in filtered {
            currentStep = .generatingPlan
            let (recs, session) = try await service.suggestNextLessons(
                for: student,
                depth: .quick
            )
            allRecs.append(contentsOf: recs)
            latestSession = session
        }
        
        // Sort by priority
        allRecs.sort { $0.priority < $1.priority }
        
        self.currentSession = latestSession
        self.recommendations = allRecs
        
        let summary = "Found \(allRecs.count) suggestions for \(filtered.count) students."
        messages.append(PlanningMessage(role: .assistant, content: summary, recommendationIDs: allRecs.map(\.id)))
        self.currentStep = .presentingPlan
    }
    
    private func fetchStudents(context: NSManagedObjectContext) -> [CDStudent] {
        let request = CDFetchRequest(CDStudent.self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)]
        let all = context.safeFetch(request)
        return TestStudentsFilter.filterVisible(all.filter(\.isEnrolled))
    }
}

// MARK: - Planning Errors

enum PlanningError: Error, LocalizedError {
    case studentNotFound
    case noStudents
    case serviceNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .studentNotFound: return "Student not found"
        case .noStudents: return "No students available for planning"
        case .serviceNotConfigured: return "Planning service not configured"
        }
    }
}
