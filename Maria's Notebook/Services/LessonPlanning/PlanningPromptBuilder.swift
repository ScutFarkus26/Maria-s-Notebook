import Foundation
import OSLog

/// Constructs prompts for each step of the AI lesson planning pipeline.
/// Each method produces a prompt that includes the relevant data context and
/// a JSON response schema for structured parsing.
@MainActor
struct PlanningPromptBuilder {
    private static let logger = Logger.ai
    
    // MARK: - Step 2: Gap Analysis
    
    /// Builds the gap analysis prompt that identifies candidate lessons and ranks them.
    /// - Parameters:
    ///   - profiles: Student readiness profiles (from Step 1)
    ///   - curriculum: Compressed curriculum summary
    ///   - preferences: Optional teacher preferences (e.g., "focus on math", "skip sensorial")
    /// - Returns: Prompt string for the gap analysis API call
    static func buildGapAnalysisPrompt(
        profiles: [StudentReadinessProfile],
        curriculum: String,
        preferences: String?
    ) -> String {
        let readinessSummary = StudentReadinessAssessor.compressedSummary(of: profiles)
        
        var prompt = """
        Analyze the following student readiness data and curriculum status to identify \
        the highest-priority lessons that should be presented next.
        
        \(readinessSummary)
        
        \(curriculum)
        """
        
        if let prefs = preferences, !prefs.isEmpty {
            prompt += "\n\nTEACHER PREFERENCES: \(prefs)"
        }
        
        prompt += """
        
        
        TASK: Identify and rank the top lesson recommendations. For each recommendation:
        1. Consider prerequisite completion and curriculum sequence
        2. Assess student readiness based on mastery signals, practice quality, and independence
        3. Prioritize students who haven't had presentations recently
        4. Suggest natural groupings when multiple students are ready for the same lesson
        5. Provide clear reasoning for each recommendation
        
        Return your response as JSON matching this schema:
        {
          "recommendations": [
            {
              "lessonName": "exact lesson name from the data",
              "subject": "subject name",
              "group": "group name",
              "studentNames": ["student names who should receive this lesson"],
              "reasoning": "brief explanation of why this lesson now for these students",
              "confidence": 0.85,
              "priority": 1,
              "suggestedDay": null
            }
          ],
          "summary": "Brief overall analysis of the class readiness state"
        }
        
        Rank by priority (1 = most urgent). Include up to 10 recommendations.
        Use exact lesson names and student names from the provided data.
        Confidence should reflect how certain you are (0.0-1.0).
        """
        
        return prompt
    }
    
    // MARK: - Step 3: Plan Synthesis
    
    /// Builds the plan synthesis prompt that schedules candidates into days.
    /// - Parameters:
    ///   - candidateJSON: JSON string of recommendations from Step 2
    ///   - students: Student names for context
    ///   - weekStart: Start date of the planning week
    /// - Returns: Prompt string for the plan synthesis API call
    static func buildPlanSynthesisPrompt(
        candidateJSON: String,
        students: [String],
        weekStart: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        
        let weekDays = (0..<5).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: weekStart)
        }
        let dayLabels = weekDays.map { formatter.string(from: $0) }
        
        return """
        Given these lesson recommendations:
        
        \(candidateJSON)
        
        Students in class: \(students.joined(separator: ", "))
        
        Week days: \(dayLabels.joined(separator: ", "))
        
        TASK: Schedule these recommendations across the week. For each day:
        1. Balance subjects - avoid clustering the same subject on one day
        2. Consider student load - don't overload any single student
        3. Group presentations that share students on the same day when practical
        4. Limit to 3-4 new presentations per day maximum
        5. Suggest student groupings for shared presentations
        
        Return your response as JSON matching this schema:
        {
          "recommendations": [
            {
              "lessonName": "exact lesson name",
              "subject": "subject name",
              "group": "group name",
              "studentNames": ["student names"],
              "reasoning": "brief scheduling rationale",
              "confidence": 0.85,
              "priority": 1,
              "suggestedDay": "Monday, Feb 24"
            }
          ],
          "groupingSuggestions": [
            {
              "lessonName": "lesson for group presentation",
              "studentNames": ["students to group together"],
              "rationale": "why these students should be grouped"
            }
          ],
          "summary": "Brief overview of the weekly plan strategy"
        }
        
        Use exact day names from the provided week days.
        Preserve lesson names and student names exactly as given.
        """
    }
    
    // MARK: - Step 4: Week Optimization (Deep)
    
    /// Builds the week optimization prompt for whole-class planning.
    /// - Parameters:
    ///   - studentPlansJSON: JSON of per-student plan data
    ///   - constraints: Any scheduling constraints
    /// - Returns: Prompt string for the week optimization API call
    static func buildWeekOptimizationPrompt(
        studentPlansJSON: String,
        constraints: String?
    ) -> String {
        var prompt = """
        Review this complete weekly lesson plan and optimize it:
        
        \(studentPlansJSON)
        """
        
        if let constraints, !constraints.isEmpty {
            prompt += "\n\nCONSTRAINTS: \(constraints)"
        }
        
        prompt += """
        
        
        TASK: Optimize the weekly plan for the whole class:
        1. Minimize context switching - cluster related subjects
        2. Ensure equitable attention across all students
        3. Identify opportunities to combine presentations for efficiency
        4. Flag any students who are overloaded or underserved
        5. Suggest any schedule swaps that improve the plan
        
        Return your response as JSON matching this schema:
        {
          "recommendations": [
            {
              "lessonName": "exact lesson name",
              "subject": "subject name",
              "group": "group name",
              "studentNames": ["student names"],
              "reasoning": "optimization rationale",
              "confidence": 0.85,
              "priority": 1,
              "suggestedDay": "day name"
            }
          ],
          "groupingSuggestions": [
            {
              "lessonName": "lesson name",
              "studentNames": ["students"],
              "rationale": "grouping rationale"
            }
          ],
          "summary": "Summary of optimizations made and overall weekly balance"
        }
        """
        
        return prompt
    }
    
    // MARK: - Follow-Up Conversation
    
    /// Builds a follow-up prompt for conversational questions.
    /// - Parameters:
    ///   - question: Teacher's follow-up question
    ///   - context: Condensed context from the current planning session
    ///   - currentPlan: Current recommendations as JSON
    /// - Returns: Prompt string for the follow-up API call
    static func buildFollowUpPrompt(
        question: String,
        context: String,
        currentPlan: String?
    ) -> String {
        var prompt = """
        CONTEXT (from current planning session):
        \(context)
        """
        
        if let plan = currentPlan {
            prompt += "\n\nCURRENT PLAN:\n\(plan)"
        }
        
        prompt += """
        
        
        TEACHER'S QUESTION: \(question)
        
        Respond helpfully and concisely. If the question asks to modify the plan, \
        return updated recommendations in the same JSON format. \
        If it's a general question, respond with plain text.
        
        If updating the plan, return JSON:
        {
          "recommendations": [...],
          "summary": "what changed and why",
          "followUpContext": "brief context for future questions"
        }
        
        If answering a general question, return JSON:
        {
          "recommendations": [],
          "summary": "your answer to the question",
          "followUpContext": "brief context for future questions"
        }
        """
        
        return prompt
    }
    
    // MARK: - Token Estimation
    
    /// Estimates token usage for a prompt and warns if over budget.
    static func estimateTokens(for prompt: String, budget: Int? = nil) -> Int {
        let estimate = TokenEstimator.estimateTokens(for: prompt)
        if let budget, estimate > budget {
            logger.warning("Prompt exceeds token budget: \(estimate)/\(budget) tokens")
        }
        return estimate
    }
}
