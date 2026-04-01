import Foundation
import CoreData
import OSLog

/// Orchestrates the AI lesson planning pipeline, composing data assembly,
/// readiness assessment, prompt construction, and API calls into a multi-step
/// planning workflow. Manages conversation state and applies recommendations.
///
/// Helpers live in:
/// - LessonPlanningService+ResponseParsing.swift  (JSON parsing)
/// - LessonPlanningService+Helpers.swift          (plan building, context, data fetching)
/// - AIConfigurationResolver.swift                (UserDefaults → AI config)
@MainActor
final class LessonPlanningService {
    static let logger = Logger.ai

    let managedObjectContext: NSManagedObjectContext
    private let mcpClient: MCPClientProtocol

    /// Resolved AI settings read from UserDefaults at init time.
    private let config: AIConfigurationResolver

    init(context: NSManagedObjectContext, mcpClient: MCPClientProtocol) {
        self.managedObjectContext = context
        self.mcpClient = mcpClient
        self.config = AIConfigurationResolver(for: .lessonPlanning)
    }

    @available(*, deprecated, message: "Use Core Data overload")
    convenience init(modelContext: NSManagedObjectContext, mcpClient: MCPClientProtocol) {
        self.init(context: modelContext, mcpClient: mcpClient)
    }

    // MARK: - Public API

    /// Suggests next lessons for a single student.
    /// Uses quick depth: local readiness + gap analysis only.
    func suggestNextLessons(
        for student: CDStudent,
        depth: PlanningDepth = .quick,
        subjectFilter: String? = nil,
        preferences: String? = nil
    ) async throws -> (recommendations: [LessonRecommendation], session: PlanningSession) {
        mcpClient.configureForFeature(.lessonPlanning)
        guard let studentID = student.id else {
            throw PlanningError.studentNotFound
        }
        var session = PlanningSession(mode: .singleStudent(studentID), depth: depth)

        // Step 1: Local readiness assessment
        let profile = StudentReadinessAssessor.assessReadiness(for: student, context: managedObjectContext)
        session.readinessProfiles = [profile]

        // Step 2: Curriculum data + gap analysis
        let curriculum = CurriculumDataAssembler.assembleCurriculumMap(for: [student], context: managedObjectContext)
        let curriculumSummary = CurriculumDataAssembler.compressedSummary(of: curriculum)

        let gapPrompt = PlanningPromptBuilder.buildGapAnalysisPrompt(
            profiles: [profile],
            curriculum: curriculumSummary,
            preferences: buildPreferencesString(subjectFilter: subjectFilter, extra: preferences)
        )

        session.tokensUsed += PlanningPromptBuilder.estimateTokens(for: gapPrompt)

        let gapResponse = try await mcpClient.generateStructuredJSON(
            prompt: gapPrompt,
            systemMessage: config.systemPrompt,
            temperature: config.temperature,
            maxTokens: 4096,
            model: config.model,
            timeout: config.timeout
        )

        var recommendations = parseRecommendations(from: gapResponse, students: [student])

        // Step 3 (standard+): Plan synthesis with day scheduling
        if depth == .standard || depth == .deep {
            let candidateJSON = encodeRecommendationsForPrompt(recommendations)
            let synthesisPrompt = PlanningPromptBuilder.buildPlanSynthesisPrompt(
                candidateJSON: candidateJSON,
                students: [student.fullName],
                weekStart: nextWeekStart()
            )

            session.tokensUsed += PlanningPromptBuilder.estimateTokens(for: synthesisPrompt)

            let synthesisResponse = try await mcpClient.generateStructuredJSON(
                prompt: synthesisPrompt,
                systemMessage: config.systemPrompt,
                temperature: config.temperature,
                maxTokens: 4096,
                model: config.model,
                timeout: config.timeout
            )

            recommendations = parseRecommendations(from: synthesisResponse, students: [student])
        }

        session.recommendations = recommendations

        // Add assistant message summarizing the plan
        let summary = recommendations.isEmpty
            ? "No recommendations found for \(student.fullName) at this time."
            : "Found \(recommendations.count) lesson recommendation"
            + "\(recommendations.count == 1 ? "" : "s") for \(student.fullName)."
        session.messages.append(PlanningMessage(
            role: .assistant,
            content: summary,
            recommendationIDs: recommendations.map(\.id)
        ))

        return (recommendations, session)
    }

    // Generates a weekly plan for the whole class.
    // swiftlint:disable:next function_body_length
    func generateWeekPlan(
        students: [CDStudent],
        weekStartDate: Date? = nil,
        preferences: String? = nil
    ) async throws -> (weekPlan: WeekPlan?, session: PlanningSession) {
        mcpClient.configureForFeature(.lessonPlanning)
        var session = PlanningSession(mode: .wholeClass, depth: .deep)
        let weekStart = weekStartDate ?? nextWeekStart()

        // Step 1: Assess readiness for all students
        let profiles = StudentReadinessAssessor.assessReadiness(for: students, context: managedObjectContext)
        session.readinessProfiles = profiles

        // Step 2: Curriculum map + gap analysis
        let curriculum = CurriculumDataAssembler.assembleCurriculumMap(for: students, context: managedObjectContext)
        let curriculumSummary = CurriculumDataAssembler.compressedSummary(of: curriculum)

        let gapPrompt = PlanningPromptBuilder.buildGapAnalysisPrompt(
            profiles: profiles,
            curriculum: curriculumSummary,
            preferences: preferences
        )

        session.tokensUsed += PlanningPromptBuilder.estimateTokens(for: gapPrompt)

        let gapResponse = try await mcpClient.generateStructuredJSON(
            prompt: gapPrompt,
            systemMessage: config.systemPrompt,
            temperature: config.temperature,
            maxTokens: 6144,
            model: config.model,
            timeout: config.timeout
        )

        let candidates = parseRecommendations(from: gapResponse, students: students)

        // Step 3: Plan synthesis
        let candidateJSON = encodeRecommendationsForPrompt(candidates)
        let synthesisPrompt = PlanningPromptBuilder.buildPlanSynthesisPrompt(
            candidateJSON: candidateJSON,
            students: students.map(\.fullName),
            weekStart: weekStart
        )

        session.tokensUsed += PlanningPromptBuilder.estimateTokens(for: synthesisPrompt)

        let synthesisResponse = try await mcpClient.generateStructuredJSON(
            prompt: synthesisPrompt,
            systemMessage: config.systemPrompt,
            temperature: config.temperature,
            maxTokens: 6144,
            model: config.model,
            timeout: config.timeout
        )

        var scheduledRecs = parseRecommendations(from: synthesisResponse, students: students)
        let groupings = parseGroupings(from: synthesisResponse, students: students)

        // Step 4: Week optimization
        let optimizationPrompt = PlanningPromptBuilder.buildWeekOptimizationPrompt(
            studentPlansJSON: encodeRecommendationsForPrompt(scheduledRecs),
            constraints: preferences
        )

        session.tokensUsed += PlanningPromptBuilder.estimateTokens(for: optimizationPrompt)

        let optimizationResponse = try await mcpClient.generateStructuredJSON(
            prompt: optimizationPrompt,
            systemMessage: config.systemPrompt,
            temperature: config.temperature,
            maxTokens: 6144,
            model: config.model,
            timeout: config.timeout
        )

        scheduledRecs = parseRecommendations(from: optimizationResponse, students: students)

        // Build week plan from scheduled recommendations
        let weekPlan = buildWeekPlan(
            from: scheduledRecs,
            groupings: groupings,
            weekStart: weekStart,
            summary: parseSummary(from: optimizationResponse)
        )

        session.weekPlan = weekPlan
        session.recommendations = scheduledRecs

        let recCount = scheduledRecs.count
        let dayCount = weekPlan.days.count
        let summary = "Generated weekly plan with \(recCount) presentations across \(dayCount) days."
        session.messages.append(PlanningMessage(
            role: .assistant,
            content: summary,
            recommendationIDs: scheduledRecs.map(\.id)
        ))

        return (weekPlan, session)
    }

    /// Handles a follow-up question in an existing planning session.
    func respondToQuestion(
        _ question: String,
        inSession session: inout PlanningSession
    ) async throws -> [LessonRecommendation] {
        mcpClient.configureForFeature(.lessonPlanning)
        // Add teacher message
        session.messages.append(PlanningMessage(role: .teacher, content: question))

        // Build condensed context (~500 tokens)
        let context = buildCondensedContext(from: session)
        let currentPlan = session.recommendations.isEmpty
            ? nil : encodeRecommendationsForPrompt(session.recommendations)

        let followUpPrompt = PlanningPromptBuilder.buildFollowUpPrompt(
            question: question,
            context: context,
            currentPlan: currentPlan
        )

        session.tokensUsed += PlanningPromptBuilder.estimateTokens(for: followUpPrompt)

        let response = try await mcpClient.generateStructuredJSON(
            prompt: followUpPrompt,
            systemMessage: config.systemPrompt,
            temperature: min(config.temperature + 0.1, 1.0),
            maxTokens: 4096,
            model: config.model,
            timeout: config.timeout
        )

        let students = fetchStudents(for: session.mode)
        let newRecs = parseRecommendations(from: response, students: students)
        let responseSummary = parseSummary(from: response)

        // Update session if new recommendations were provided
        if !newRecs.isEmpty {
            session.recommendations = newRecs
        }

        session.messages.append(PlanningMessage(
            role: .assistant,
            content: responseSummary,
            recommendationIDs: newRecs.map(\.id)
        ))

        return newRecs
    }

    /// Creates CDLessonAssignment drafts from accepted recommendations.
    func applyRecommendations(
        _ recommendations: [LessonRecommendation],
        scheduledDates: [UUID: Date] = [:]
    ) throws -> [CDLessonAssignment] {
        let allLessons = fetchAllLessons()

        var created: [CDLessonAssignment] = []

        for rec in recommendations {
            guard let lesson = allLessons.first(where: { $0.id == rec.lessonID }),
                  let lessonID = lesson.id else {
                Self.logger.warning("CDLesson not found for recommendation: \(rec.lessonName)")
                continue
            }

            // Use Core Data factory — auto-inserts into context
            let la = PresentationFactory.makeDraft(
                lessonID: lessonID,
                studentIDs: rec.studentIDs,
                context: managedObjectContext
            )

            // Schedule if date provided
            if let date = scheduledDates[rec.id] {
                la.scheduledFor = date
            }

            created.append(la)
        }

        return created
    }
}
