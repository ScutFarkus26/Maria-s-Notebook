//
//  StudentAnalysisService.swift
//  Maria's Notebook
//
//  MCP-powered service for analyzing student development patterns and progress
//

import Foundation
import SwiftData

/// Service that leverages MCP tools to analyze student data and provide actionable insights
@MainActor
final class StudentAnalysisService {
    
    // MARK: - Dependencies
    
    private let modelContext: ModelContext
    private let mcpClient: MCPClientProtocol
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext, mcpClient: MCPClientProtocol) {
        self.modelContext = modelContext
        self.mcpClient = mcpClient
    }
    
    // MARK: - Public API
    
    /// Analyzes a student's recent activity and generates development insights
    /// - Parameters:
    ///   - student: The student to analyze
    ///   - lookbackDays: Number of days to analyze (default: 30)
    /// - Returns: A DevelopmentSnapshot containing analysis results
    func analyzeStudent(_ student: Student, lookbackDays: Int = 30) async throws -> DevelopmentSnapshot {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        
        // Gather student data from the past N days
        let studentData = try await gatherStudentData(student: student, since: cutoffDate)
        
        // Use MCP to analyze patterns
        let analysis = try await performMCPAnalysis(studentData: studentData, student: student)
        
        // Create snapshot
        let snapshot = DevelopmentSnapshot(
            id: UUID(),
            studentID: student.id.uuidString,
            generatedAt: Date(),
            lookbackDays: lookbackDays,
            analysisVersion: "1.0",
            
            // Summary
            overallProgress: analysis.overallProgress,
            keyStrengths: analysis.keyStrengths,
            areasForGrowth: analysis.areasForGrowth,
            developmentalMilestones: analysis.developmentalMilestones,
            
            // Insights
            observedPatterns: analysis.observedPatterns,
            behavioralTrends: analysis.behavioralTrends,
            socialEmotionalInsights: analysis.socialEmotionalInsights,
            
            // Recommendations
            recommendedNextLessons: analysis.recommendedNextLessons,
            suggestedPracticeFocus: analysis.suggestedPracticeFocus,
            interventionSuggestions: analysis.interventionSuggestions,
            
            // Metrics
            totalNotesAnalyzed: studentData.notes.count,
            practiceSessionsAnalyzed: studentData.practiceSessions.count,
            workCompletionsAnalyzed: studentData.workCompletions.count,
            averagePracticeQuality: studentData.averagePracticeQuality,
            independenceLevel: studentData.averageIndependenceLevel,
            
            // Raw data for reference
            rawAnalysisJSON: analysis.rawJSON
        )
        
        // Insert the snapshot into the model context
        modelContext.insert(snapshot)
        
        return snapshot
    }
    
    /// Generates a parent-friendly summary from a development snapshot
    func generateParentSummary(snapshot: DevelopmentSnapshot) async throws -> String {
        let prompt = """
        Create a warm, encouraging 2-3 paragraph summary for parents about their child's recent progress.
        
        Focus on:
        - Key strengths: \(snapshot.keyStrengths.joined(separator: ", "))
        - Areas for growth: \(snapshot.areasForGrowth.joined(separator: ", "))
        - Overall progress: \(snapshot.overallProgress)
        
        Use positive, growth-oriented language. Avoid educational jargon.
        """
        
        return try await mcpClient.generateText(prompt: prompt, temperature: 0.7)
    }
    
    /// Compares two snapshots to show progress over time
    func compareSnapshots(earlier: DevelopmentSnapshot, later: DevelopmentSnapshot) -> ProgressComparison {
        var improvements: [String] = []
        var regressions: [String] = []
        var newMilestones: [String] = []
        
        // Compare independence levels
        if let earlierIndependence = earlier.independenceLevel,
           let laterIndependence = later.independenceLevel {
            if laterIndependence > earlierIndependence {
                improvements.append("Independence increased from \(earlierIndependence) to \(laterIndependence)")
            } else if laterIndependence < earlierIndependence {
                regressions.append("Independence decreased from \(earlierIndependence) to \(laterIndependence)")
            }
        }
        
        // Compare practice quality
        if let earlierQuality = earlier.averagePracticeQuality,
           let laterQuality = later.averagePracticeQuality {
            if laterQuality > earlierQuality {
                improvements.append("Practice quality improved from \(String(format: FormattingConstants.singleDecimal, earlierQuality)) to \(String(format: FormattingConstants.singleDecimal, laterQuality))")
            } else if laterQuality < earlierQuality {
                regressions.append("Practice quality decreased from \(String(format: FormattingConstants.singleDecimal, earlierQuality)) to \(String(format: FormattingConstants.singleDecimal, laterQuality))")
            }
        }
        
        // Find new milestones
        let earlierMilestones = Set(earlier.developmentalMilestones)
        let laterMilestones = Set(later.developmentalMilestones)
        newMilestones = Array(laterMilestones.subtracting(earlierMilestones))
        
        // Find new strengths
        let earlierStrengths = Set(earlier.keyStrengths)
        let laterStrengths = Set(later.keyStrengths)
        let emergingStrengths = Array(laterStrengths.subtracting(earlierStrengths))
        
        return ProgressComparison(
            improvements: improvements,
            regressions: regressions,
            newMilestones: newMilestones,
            emergingStrengths: emergingStrengths,
            timeSpan: later.generatedAt.timeIntervalSince(earlier.generatedAt)
        )
    }
    
    // MARK: - Private Helpers
    
    private func gatherStudentData(student: Student, since: Date) async throws -> StudentDataPackage {
        // Fetch notes for this student
        let studentID = student.id
        let sinceDate = since
        let noteRepository = NoteRepository(context: modelContext)
        let notes = noteRepository
            .fetchNotesForStudent(studentID: studentID)
            .filter { $0.createdAt >= sinceDate }
        
        // Fetch practice sessions
        let practiceDescriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate<PracticeSession> { session in
                session.date >= sinceDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let allPracticeSessions = try modelContext.fetch(practiceDescriptor)
        let practiceSessions = allPracticeSessions.filter { $0.includes(studentID: student.id) }
        
        // Fetch work completions
        let completionDescriptor = FetchDescriptor<WorkCompletionRecord>(
            predicate: #Predicate<WorkCompletionRecord> { record in
                record.completedAt >= sinceDate
            },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        let allCompletions = try modelContext.fetch(completionDescriptor)
        let workCompletions = allCompletions.filter { $0.studentID == student.id.uuidString }
        
        // Calculate metrics
        let practiceQualities = practiceSessions.compactMap { $0.practiceQuality }
        let avgQuality = practiceQualities.isEmpty ? nil : Double(practiceQualities.reduce(0, +)) / Double(practiceQualities.count)
        
        let independenceLevels = practiceSessions.compactMap { $0.independenceLevel }
        let avgIndependence = independenceLevels.isEmpty ? nil : Double(independenceLevels.reduce(0, +)) / Double(independenceLevels.count)
        
        return StudentDataPackage(
            student: student,
            notes: notes,
            practiceSessions: practiceSessions,
            workCompletions: workCompletions,
            averagePracticeQuality: avgQuality,
            averageIndependenceLevel: avgIndependence,
            dateRange: since...Date()
        )
    }
    
    private func performMCPAnalysis(studentData: StudentDataPackage, student: Student) async throws -> MCPAnalysisResult {
        // Prepare structured data for MCP analysis
        let analysisPayload = prepareAnalysisPayload(studentData: studentData, student: student)
        
        // Call MCP tool for pattern analysis
        let prompt = """
        You are an experienced Montessori guide analyzing a student's recent development.
        
        Student: \(student.fullName) (Age: \(student.birthday.age ?? 0), Level: \(student.level.rawValue))
        Analysis Period: \(studentData.dateRange.lowerBound.formatted(date: .abbreviated, time: .omitted)) to \(studentData.dateRange.upperBound.formatted(date: .abbreviated, time: .omitted))
        
        DATA SUMMARY:
        - Total Notes: \(studentData.notes.count)
        - Practice Sessions: \(studentData.practiceSessions.count)
        - Work Completions: \(studentData.workCompletions.count)
        - Average Practice Quality: \(studentData.averagePracticeQuality.map { $0.formatAsScore() } ?? "N/A")
        - Average Independence: \(studentData.averageIndependenceLevel.map { $0.formatAsScore() } ?? "N/A")
        
        RECENT OBSERVATIONS:
        \(analysisPayload.observationsSummary)
        
        PRACTICE PATTERNS:
        \(analysisPayload.practiceSummary)
        
        BEHAVIORAL FLAGS:
        \(analysisPayload.behavioralFlags)
        
        Based on this data, provide a comprehensive analysis in the following JSON format:
        {
            "overallProgress": "1-2 sentence summary of overall development",
            "keyStrengths": ["strength 1", "strength 2", "strength 3"],
            "areasForGrowth": ["area 1", "area 2"],
            "developmentalMilestones": ["milestone 1", "milestone 2"],
            "observedPatterns": ["pattern 1", "pattern 2"],
            "behavioralTrends": ["trend 1", "trend 2"],
            "socialEmotionalInsights": ["insight 1", "insight 2"],
            "recommendedNextLessons": ["lesson recommendation 1", "lesson recommendation 2"],
            "suggestedPracticeFocus": ["practice focus 1", "practice focus 2"],
            "interventionSuggestions": ["suggestion 1", "suggestion 2"]
        }
        
        Guidelines:
        - Be specific and evidence-based
        - Use Montessori terminology appropriately
        - Focus on growth mindset language
        - Identify both academic and social-emotional development
        - Suggest concrete next steps
        """
        
        let response = try await mcpClient.generateStructuredJSON(prompt: prompt, temperature: 0.3)
        
        return try parseAnalysisResponse(json: response)
    }
    
    private func prepareAnalysisPayload(studentData: StudentDataPackage, student: Student) -> AnalysisPayload {
        // Summarize observations from notes
        let notesByCategory = Dictionary(grouping: studentData.notes, by: { $0.category })
        var observationsSummary = ""
        for (category, notes) in notesByCategory.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            observationsSummary += "\n\(category.rawValue.capitalized) (\(notes.count) notes):\n"
            for note in notes.prefix(3) {
                observationsSummary += "  - \(note.body.prefix(100))\n"
            }
        }
        
        // Summarize practice patterns
        var practiceSummary = ""
        if !studentData.practiceSessions.isEmpty {
            let sessionsWithBreakthrough = studentData.practiceSessions.filter { $0.madeBreakthrough }.count
            let sessionsNeedingHelp = studentData.practiceSessions.filter { $0.askedForHelp }.count
            let sessionsHelpingPeers = studentData.practiceSessions.filter { $0.helpedPeer }.count
            let sessionsStruggling = studentData.practiceSessions.filter { $0.struggledWithConcept }.count
            
            practiceSummary = """
            - Breakthrough moments: \(sessionsWithBreakthrough)
            - Asked for help: \(sessionsNeedingHelp)
            - Helped peers: \(sessionsHelpingPeers)
            - Struggled with concept: \(sessionsStruggling)
            """
        }
        
        // Behavioral flags
        var behavioralFlags: [String] = []
        let readyForCheckIn = studentData.practiceSessions.filter { $0.readyForCheckIn }.count
        let readyForAssessment = studentData.practiceSessions.filter { $0.readyForAssessment }.count
        let needsReteaching = studentData.practiceSessions.filter { $0.needsReteaching }.count
        
        if readyForCheckIn > 0 {
            behavioralFlags.append("Ready for check-in: \(readyForCheckIn) times")
        }
        if readyForAssessment > 0 {
            behavioralFlags.append("Ready for assessment: \(readyForAssessment) times")
        }
        if needsReteaching > 0 {
            behavioralFlags.append("Needs reteaching: \(needsReteaching) times")
        }
        
        return AnalysisPayload(
            observationsSummary: observationsSummary,
            practiceSummary: practiceSummary,
            behavioralFlags: behavioralFlags.joined(separator: "\n")
        )
    }
    
    private func parseAnalysisResponse(json: String) throws -> MCPAnalysisResult {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let response = try decoder.decode(MCPAnalysisResponse.self, from: data)
        
        return MCPAnalysisResult(
            overallProgress: response.overallProgress,
            keyStrengths: response.keyStrengths,
            areasForGrowth: response.areasForGrowth,
            developmentalMilestones: response.developmentalMilestones,
            observedPatterns: response.observedPatterns,
            behavioralTrends: response.behavioralTrends,
            socialEmotionalInsights: response.socialEmotionalInsights,
            recommendedNextLessons: response.recommendedNextLessons,
            suggestedPracticeFocus: response.suggestedPracticeFocus,
            interventionSuggestions: response.interventionSuggestions,
            rawJSON: json
        )
    }
}

// MARK: - Supporting Types

struct StudentDataPackage {
    let student: Student
    let notes: [Note]
    let practiceSessions: [PracticeSession]
    let workCompletions: [WorkCompletionRecord]
    let averagePracticeQuality: Double?
    let averageIndependenceLevel: Double?
    let dateRange: ClosedRange<Date>
}

struct AnalysisPayload {
    let observationsSummary: String
    let practiceSummary: String
    let behavioralFlags: String
}

struct MCPAnalysisResult {
    let overallProgress: String
    let keyStrengths: [String]
    let areasForGrowth: [String]
    let developmentalMilestones: [String]
    let observedPatterns: [String]
    let behavioralTrends: [String]
    let socialEmotionalInsights: [String]
    let recommendedNextLessons: [String]
    let suggestedPracticeFocus: [String]
    let interventionSuggestions: [String]
    let rawJSON: String
}

struct ProgressComparison {
    let improvements: [String]
    let regressions: [String]
    let newMilestones: [String]
    let emergingStrengths: [String]
    let timeSpan: TimeInterval
    
    var hasSignificantChanges: Bool {
        !improvements.isEmpty || !newMilestones.isEmpty || !emergingStrengths.isEmpty
    }
}
