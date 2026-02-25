import Foundation
import SwiftData
import OSLog

/// Orchestrates the AI lesson planning pipeline, composing data assembly,
/// readiness assessment, prompt construction, and API calls into a multi-step
/// planning workflow. Manages conversation state and applies recommendations.
@MainActor
final class LessonPlanningService {
    private static let logger = Logger.ai
    
    private let modelContext: ModelContext
    private let mcpClient: MCPClientProtocol
    
    init(modelContext: ModelContext, mcpClient: MCPClientProtocol) {
        self.modelContext = modelContext
        self.mcpClient = mcpClient
    }
    
    // MARK: - Public API
    
    /// Suggests next lessons for a single student.
    /// Uses quick depth: local readiness + gap analysis only.
    func suggestNextLessons(
        for student: Student,
        depth: PlanningDepth = .quick,
        subjectFilter: String? = nil,
        preferences: String? = nil
    ) async throws -> (recommendations: [LessonRecommendation], session: PlanningSession) {
        var session = PlanningSession(mode: .singleStudent(student.id), depth: depth)
        
        // Step 1: Local readiness assessment
        let profile = StudentReadinessAssessor.assessReadiness(for: student, modelContext: modelContext)
        session.readinessProfiles = [profile]
        
        // Step 2: Curriculum data + gap analysis
        let curriculum = CurriculumDataAssembler.assembleCurriculumMap(for: [student], modelContext: modelContext)
        let curriculumSummary = CurriculumDataAssembler.compressedSummary(of: curriculum)
        
        let gapPrompt = PlanningPromptBuilder.buildGapAnalysisPrompt(
            profiles: [profile],
            curriculum: curriculumSummary,
            preferences: buildPreferencesString(subjectFilter: subjectFilter, extra: preferences)
        )
        
        session.tokensUsed += PlanningPromptBuilder.estimateTokens(for: gapPrompt)
        
        let gapResponse = try await mcpClient.generateStructuredJSON(
            prompt: gapPrompt,
            systemMessage: AIPrompts.lessonPlanningAssistant,
            temperature: 0.3,
            maxTokens: 4096
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
                systemMessage: AIPrompts.lessonPlanningAssistant,
                temperature: 0.3,
                maxTokens: 4096
            )
            
            recommendations = parseRecommendations(from: synthesisResponse, students: [student])
        }
        
        session.recommendations = recommendations
        
        // Add assistant message summarizing the plan
        let summary = recommendations.isEmpty
            ? "No recommendations found for \(student.fullName) at this time."
            : "Found \(recommendations.count) lesson recommendation\(recommendations.count == 1 ? "" : "s") for \(student.fullName)."
        session.messages.append(PlanningMessage(
            role: .assistant,
            content: summary,
            recommendationIDs: recommendations.map { $0.id }
        ))
        
        return (recommendations, session)
    }
    
    /// Generates a weekly plan for the whole class.
    func generateWeekPlan(
        students: [Student],
        weekStartDate: Date? = nil,
        preferences: String? = nil
    ) async throws -> (weekPlan: WeekPlan?, session: PlanningSession) {
        var session = PlanningSession(mode: .wholeClass, depth: .deep)
        let weekStart = weekStartDate ?? nextWeekStart()
        
        // Step 1: Assess readiness for all students
        let profiles = StudentReadinessAssessor.assessReadiness(for: students, modelContext: modelContext)
        session.readinessProfiles = profiles
        
        // Step 2: Curriculum map + gap analysis
        let curriculum = CurriculumDataAssembler.assembleCurriculumMap(for: students, modelContext: modelContext)
        let curriculumSummary = CurriculumDataAssembler.compressedSummary(of: curriculum)
        
        let gapPrompt = PlanningPromptBuilder.buildGapAnalysisPrompt(
            profiles: profiles,
            curriculum: curriculumSummary,
            preferences: preferences
        )
        
        session.tokensUsed += PlanningPromptBuilder.estimateTokens(for: gapPrompt)
        
        let gapResponse = try await mcpClient.generateStructuredJSON(
            prompt: gapPrompt,
            systemMessage: AIPrompts.lessonPlanningAssistant,
            temperature: 0.3,
            maxTokens: 6144
        )
        
        let candidates = parseRecommendations(from: gapResponse, students: students)
        
        // Step 3: Plan synthesis
        let candidateJSON = encodeRecommendationsForPrompt(candidates)
        let synthesisPrompt = PlanningPromptBuilder.buildPlanSynthesisPrompt(
            candidateJSON: candidateJSON,
            students: students.map { $0.fullName },
            weekStart: weekStart
        )
        
        session.tokensUsed += PlanningPromptBuilder.estimateTokens(for: synthesisPrompt)
        
        let synthesisResponse = try await mcpClient.generateStructuredJSON(
            prompt: synthesisPrompt,
            systemMessage: AIPrompts.lessonPlanningAssistant,
            temperature: 0.3,
            maxTokens: 6144
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
            systemMessage: AIPrompts.lessonPlanningAssistant,
            temperature: 0.3,
            maxTokens: 6144
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
        
        let summary = "Generated weekly plan with \(scheduledRecs.count) presentations across \(weekPlan.days.count) days."
        session.messages.append(PlanningMessage(
            role: .assistant,
            content: summary,
            recommendationIDs: scheduledRecs.map { $0.id }
        ))
        
        return (weekPlan, session)
    }
    
    /// Handles a follow-up question in an existing planning session.
    func respondToQuestion(
        _ question: String,
        inSession session: inout PlanningSession
    ) async throws -> [LessonRecommendation] {
        // Add teacher message
        session.messages.append(PlanningMessage(role: .teacher, content: question))
        
        // Build condensed context (~500 tokens)
        let context = buildCondensedContext(from: session)
        let currentPlan = session.recommendations.isEmpty ? nil : encodeRecommendationsForPrompt(session.recommendations)
        
        let followUpPrompt = PlanningPromptBuilder.buildFollowUpPrompt(
            question: question,
            context: context,
            currentPlan: currentPlan
        )
        
        session.tokensUsed += PlanningPromptBuilder.estimateTokens(for: followUpPrompt)
        
        let response = try await mcpClient.generateStructuredJSON(
            prompt: followUpPrompt,
            systemMessage: AIPrompts.lessonPlanningAssistant,
            temperature: 0.4,
            maxTokens: 4096
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
            recommendationIDs: newRecs.map { $0.id }
        ))
        
        return newRecs
    }
    
    /// Creates LessonAssignment drafts from accepted recommendations.
    func applyRecommendations(
        _ recommendations: [LessonRecommendation],
        scheduledDates: [UUID: Date] = [:]
    ) throws -> [LessonAssignment] {
        let allLessons = fetchAllLessons()
        let allStudents = fetchAllStudents()
        let coordinator = DualWriteCoordinator(context: modelContext)
        
        var created: [LessonAssignment] = []
        
        for rec in recommendations {
            guard let lesson = allLessons.first(where: { $0.id == rec.lessonID }) else {
                Self.logger.warning("Lesson not found for recommendation: \(rec.lessonName)")
                continue
            }
            
            let studentUUIDs = rec.studentIDs
            let relatedStudents = allStudents.filter { studentUUIDs.contains($0.id) }
            
            do {
                let (_, la) = try coordinator.createDraft(
                    lessonID: lesson.id,
                    studentIDs: studentUUIDs
                )
                
                PresentationFactory.attachRelationships(
                    to: la,
                    lesson: lesson,
                    students: relatedStudents
                )
                
                // Schedule if date provided
                if let date = scheduledDates[rec.id] {
                    la.schedule(for: date, using: Calendar.current)
                }
                
                created.append(la)
            } catch {
                Self.logger.warning("Failed to create draft for \(rec.lessonName): \(error)")
            }
        }
        
        return created
    }
    
    // MARK: - Response Parsing
    
    private func parseRecommendations(from jsonString: String, students: [Student]) -> [LessonRecommendation] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        
        do {
            let response = try JSONDecoder().decode(PlanningResponse.self, from: data)
            let allLessons = fetchAllLessons()
            let studentNameMap = Dictionary(uniqueKeysWithValues: students.map { ($0.fullName.lowercased(), $0.id) })
            
            return response.recommendations.compactMap { apiRec in
                // Resolve lesson ID from name
                let lesson = allLessons.first { $0.name.lowercased() == apiRec.lessonName.lowercased() }
                    ?? allLessons.first { $0.name.lowercased().contains(apiRec.lessonName.lowercased()) }
                
                guard let lessonID = lesson?.id else {
                    Self.logger.info("Could not resolve lesson: \(apiRec.lessonName)")
                    return nil
                }
                
                // Resolve student IDs from names
                let resolvedStudentIDs = apiRec.studentNames.compactMap { name -> UUID? in
                    studentNameMap[name.lowercased()]
                        ?? studentNameMap.first { $0.key.contains(name.lowercased().components(separatedBy: " ").first ?? "") }?.value
                }
                
                return LessonRecommendation(
                    lessonID: lessonID,
                    lessonName: lesson?.name ?? apiRec.lessonName,
                    subject: apiRec.subject,
                    group: apiRec.group,
                    studentIDs: resolvedStudentIDs,
                    studentNames: apiRec.studentNames,
                    reasoning: apiRec.reasoning,
                    confidence: apiRec.confidence,
                    priority: apiRec.priority,
                    suggestedDay: apiRec.suggestedDay
                )
            }
        } catch {
            Self.logger.warning("Failed to parse planning response: \(error)")
            return []
        }
    }
    
    private func parseGroupings(from jsonString: String, students: [Student]) -> [GroupingSuggestion] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        
        do {
            let response = try JSONDecoder().decode(PlanningResponse.self, from: data)
            let allLessons = fetchAllLessons()
            let studentNameMap = Dictionary(uniqueKeysWithValues: students.map { ($0.fullName.lowercased(), $0.id) })
            
            return (response.groupingSuggestions ?? []).compactMap { apiGroup in
                let lesson = allLessons.first { $0.name.lowercased() == apiGroup.lessonName.lowercased() }
                guard let lessonID = lesson?.id else { return nil }
                
                let studentIDs = apiGroup.studentNames.compactMap { name -> UUID? in
                    studentNameMap[name.lowercased()]
                }
                
                return GroupingSuggestion(
                    lessonID: lessonID,
                    lessonName: lesson?.name ?? apiGroup.lessonName,
                    studentIDs: studentIDs,
                    studentNames: apiGroup.studentNames,
                    rationale: apiGroup.rationale
                )
            }
        } catch {
            return []
        }
    }
    
    private func parseSummary(from jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8) else { return "" }
        
        do {
            let response = try JSONDecoder().decode(PlanningResponse.self, from: data)
            return response.summary ?? "Plan generated."
        } catch {
            return jsonString.prefix(500).description
        }
    }
    
    // MARK: - Week Plan Building
    
    private func buildWeekPlan(
        from recommendations: [LessonRecommendation],
        groupings: [GroupingSuggestion],
        weekStart: Date,
        summary: String
    ) -> WeekPlan {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        
        let weekDays = (0..<5).compactMap { offset -> (String, Date)? in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return (formatter.string(from: date), date)
        }
        
        var days = weekDays.map { WeekPlan.DayPlanEntry(dayName: $0.0, date: $0.1) }
        
        // Assign recommendations to days
        for rec in recommendations {
            if let dayName = rec.suggestedDay,
               let dayIndex = days.firstIndex(where: { $0.dayName.lowercased().hasPrefix(dayName.lowercased().prefix(3).description) }) {
                days[dayIndex].recommendations.append(rec)
            } else {
                // Find the day with fewest recommendations
                if let minIndex = days.indices.min(by: { days[$0].recommendations.count < days[$1].recommendations.count }) {
                    days[minIndex].recommendations.append(rec)
                }
            }
        }
        
        return WeekPlan(
            weekStartDate: weekStart,
            days: days,
            groupings: groupings,
            summary: summary
        )
    }
    
    // MARK: - Context Helpers
    
    private func buildCondensedContext(from session: PlanningSession) -> String {
        var lines: [String] = []
        
        // Mode description
        switch session.mode {
        case .singleStudent(let id):
            let name = session.readinessProfiles.first { $0.studentID == id }?.studentName ?? "student"
            lines.append("Planning for: \(name)")
        case .wholeClass:
            lines.append("Whole-class weekly planning")
        case .quickSuggest(let ids):
            lines.append("Quick suggestions for \(ids.count) students")
        }
        
        // Readiness summary (very condensed)
        for profile in session.readinessProfiles.prefix(5) {
            let subjects = profile.subjectReadiness.filter { $0.nextLessonID != nil }.prefix(3)
            let subjectStr = subjects.map { "\($0.subject):\($0.nextLessonName ?? "?")" }.joined(separator: ", ")
            lines.append("\(profile.studentName): \(subjectStr)")
        }
        
        // Include recent messages (condensed)
        let recentMessages = session.messages.suffix(4)
        for msg in recentMessages {
            let prefix = msg.role == .teacher ? "Teacher" : "Assistant"
            lines.append("\(prefix): \(msg.content.prefix(150))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func encodeRecommendationsForPrompt(_ recs: [LessonRecommendation]) -> String {
        let simplified = recs.map { rec in
            [
                "lessonName": rec.lessonName,
                "subject": rec.subject,
                "group": rec.group,
                "studentNames": rec.studentNames.joined(separator: ", "),
                "reasoning": rec.reasoning,
                "confidence": String(format: "%.2f", rec.confidence),
                "priority": "\(rec.priority)",
                "suggestedDay": rec.suggestedDay ?? ""
            ]
        }
        
        guard let data = try? JSONSerialization.data(withJSONObject: simplified, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }
    
    private func buildPreferencesString(subjectFilter: String?, extra: String?) -> String? {
        var parts: [String] = []
        if let subject = subjectFilter {
            parts.append("Focus on \(subject)")
        }
        if let extra {
            parts.append(extra)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }
    
    // MARK: - Data Fetching
    
    private func fetchAllLessons() -> [Lesson] {
        let descriptor = FetchDescriptor<Lesson>(
            sortBy: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.group), SortDescriptor(\Lesson.orderInGroup)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    private func fetchAllStudents() -> [Student] {
        let descriptor = FetchDescriptor<Student>(sortBy: [SortDescriptor(\Student.lastName)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    private func fetchStudents(for mode: PlanningMode) -> [Student] {
        let allStudents = fetchAllStudents()
        switch mode {
        case .singleStudent(let id):
            return allStudents.filter { $0.id == id }
        case .wholeClass:
            return allStudents
        case .quickSuggest(let ids):
            let idSet = Set(ids)
            return allStudents.filter { idSet.contains($0.id) }
        }
    }
    
    private func nextWeekStart() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // Next Monday
        let daysUntilMonday = (9 - weekday) % 7
        return calendar.date(byAdding: .day, value: daysUntilMonday == 0 ? 7 : daysUntilMonday, to: today) ?? today
    }
}
