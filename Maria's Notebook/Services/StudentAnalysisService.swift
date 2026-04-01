//
//  StudentAnalysisService.swift
//  Maria's Notebook
//
//  MCP-powered service for analyzing student development patterns and progress
//

import Foundation
import CoreData

/// Service that leverages MCP tools to analyze student data and provide actionable insights
@MainActor
final class StudentAnalysisService {

    // MARK: - Dependencies

    private let modelContext: NSManagedObjectContext
    private let mcpClient: MCPClientProtocol

    // MARK: - Initialization

    init(modelContext: NSManagedObjectContext, mcpClient: MCPClientProtocol) {
        self.modelContext = modelContext
        self.mcpClient = mcpClient
    }

    // Deprecated ModelContext init removed - no longer needed with Core Data.

    // MARK: - Public API

    /// Analyzes a student's recent activity and generates development insights
    /// - Parameters:
    ///   - student: The student to analyze
    ///   - lookbackDays: Number of days to analyze (default: 30)
    /// - Returns: A CDDevelopmentSnapshotEntity containing analysis results
    func analyzeStudent(_ student: CDStudent, lookbackDays: Int = 30) async throws -> CDDevelopmentSnapshotEntity {
        mcpClient.configureForFeature(.chat)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()

        // Gather student data from the past N days
        let studentData = try await gatherStudentData(student: student, since: cutoffDate)

        // Use MCP to analyze patterns
        let analysis = try await performMCPAnalysis(studentData: studentData, student: student)

        // Create snapshot as a Core Data entity (automatically inserted into context)
        let snapshot = CDDevelopmentSnapshotEntity(context: modelContext)
        snapshot.id = UUID()
        snapshot.studentID = student.id?.uuidString ?? ""
        snapshot.generatedAt = Date()
        snapshot.lookbackDays = Int64(lookbackDays)
        snapshot.analysisVersion = "1.0"

        // Summary
        snapshot.overallProgress = analysis.overallProgress
        snapshot.keyStrengths = analysis.keyStrengths
        snapshot.areasForGrowth = analysis.areasForGrowth
        snapshot.developmentalMilestones = analysis.developmentalMilestones

        // Insights
        snapshot.observedPatterns = analysis.observedPatterns
        snapshot.behavioralTrends = analysis.behavioralTrends
        snapshot.socialEmotionalInsights = analysis.socialEmotionalInsights

        // Recommendations
        snapshot.recommendedNextLessons = analysis.recommendedNextLessons
        snapshot.suggestedPracticeFocus = analysis.suggestedPracticeFocus
        snapshot.interventionSuggestions = analysis.interventionSuggestions

        // Metrics
        snapshot.totalNotesAnalyzed = Int64(studentData.notes.count)
        snapshot.practiceSessionsAnalyzed = Int64(studentData.practiceSessions.count)
        snapshot.workCompletionsAnalyzed = Int64(studentData.workCompletions.count)
        snapshot.averagePracticeQuality = studentData.averagePracticeQuality ?? 0
        snapshot.independenceLevel = studentData.averageIndependenceLevel ?? 0

        // Raw data for reference
        snapshot.rawAnalysisJSON = analysis.rawJSON

        return snapshot
    }

    /// Generates a parent-friendly summary from a development snapshot
    func generateParentSummary(snapshot: CDDevelopmentSnapshotEntity) async throws -> String {
        mcpClient.configureForFeature(.chat)
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
    func compareSnapshots(earlier: CDDevelopmentSnapshotEntity, later: CDDevelopmentSnapshotEntity) -> ProgressComparison {
        var improvements: [String] = []
        var regressions: [String] = []
        var newMilestones: [String] = []

        // Compare independence levels
        let earlierIndependence = earlier.independenceLevel
        let laterIndependence = later.independenceLevel
        if earlierIndependence > 0 && laterIndependence > 0 {
            if laterIndependence > earlierIndependence {
                improvements.append("Independence increased from \(earlierIndependence) to \(laterIndependence)")
            } else if laterIndependence < earlierIndependence {
                regressions.append("Independence decreased from \(earlierIndependence) to \(laterIndependence)")
            }
        }

        // Compare practice quality
        let earlierQuality = earlier.averagePracticeQuality
        let laterQuality = later.averagePracticeQuality
        if earlierQuality > 0 && laterQuality > 0 {
            if laterQuality > earlierQuality {
                let earlierStr = String(format: FormattingConstants.singleDecimal, earlierQuality)
                let laterStr = String(format: FormattingConstants.singleDecimal, laterQuality)
                improvements.append("Practice quality improved from \(earlierStr) to \(laterStr)")
            } else if laterQuality < earlierQuality {
                let earlierStr = String(format: FormattingConstants.singleDecimal, earlierQuality)
                let laterStr = String(format: FormattingConstants.singleDecimal, laterQuality)
                regressions.append("Practice quality decreased from \(earlierStr) to \(laterStr)")
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
            timeSpan: (later.generatedAt ?? Date()).timeIntervalSince(earlier.generatedAt ?? Date())
        )
    }

    // MARK: - Private Helpers

    private func gatherStudentData(student: CDStudent, since: Date) async throws -> StudentDataPackage {
        // Fetch notes for this student
        guard let studentID = student.id else {
            return StudentDataPackage(
                student: student, notes: [], practiceSessions: [],
                workCompletions: [], averagePracticeQuality: nil,
                averageIndependenceLevel: nil, dateRange: since...Date()
            )
        }

        // Fetch notes via Core Data
        let noteRequest = CDFetchRequest(CDNote.self)
        noteRequest.predicate = NSPredicate(
            format: "searchIndexStudentID == %@ AND createdAt >= %@",
            studentID as CVarArg, since as NSDate
        )
        noteRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let notes = (try? modelContext.fetch(noteRequest)) ?? []

        // Fetch practice sessions
        let practiceRequest = CDFetchRequest(CDPracticeSession.self)
        practiceRequest.predicate = NSPredicate(format: "date >= %@", since as NSDate)
        practiceRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        let allPracticeSessions = try modelContext.fetch(practiceRequest)
        let practiceSessions = allPracticeSessions.filter { $0.includes(studentID: studentID) }

        // Fetch work completions -- filter by studentID in the predicate so SQLite
        // only returns records for this student instead of loading all completions.
        let studentIDString = studentID.uuidString
        let completionRequest = CDFetchRequest(CDWorkCompletionRecord.self)
        completionRequest.predicate = NSPredicate(
            format: "completedAt >= %@ AND studentID == %@",
            since as NSDate, studentIDString
        )
        completionRequest.sortDescriptors = [NSSortDescriptor(key: "completedAt", ascending: false)]
        let workCompletions = try modelContext.fetch(completionRequest)

        // Calculate metrics
        let practiceQualities = practiceSessions.compactMap(\.practiceQualityValue)
        let avgQuality: Double? = practiceQualities.isEmpty ? nil :
            Double(practiceQualities.reduce(0, +)) / Double(practiceQualities.count)

        let independenceLevels = practiceSessions.compactMap(\.independenceLevelValue)
        let avgIndependence: Double? = independenceLevels.isEmpty ? nil :
            Double(independenceLevels.reduce(0, +)) / Double(independenceLevels.count)

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

    private func performMCPAnalysis(
        studentData: StudentDataPackage, student: CDStudent
    ) async throws -> MCPAnalysisResult {
        // Prepare structured data for MCP analysis
        let analysisPayload = prepareAnalysisPayload(studentData: studentData, student: student)

        // Call MCP tool for pattern analysis
        let prompt = """
        You are an experienced Montessori guide analyzing a student's recent development.

        CDStudent: \(student.fullName) (Age: \(student.birthday?.age ?? 0), Level: \(student.level.rawValue))
        Analysis Period: \(studentData.dateRange.lowerBound.formatted(date: .abbreviated, time: .omitted)) to \
        \(studentData.dateRange.upperBound.formatted(date: .abbreviated, time: .omitted))

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

    private func prepareAnalysisPayload(studentData: StudentDataPackage, student: CDStudent) -> AnalysisPayload {
        // Summarize observations from notes
        let notesByTag = Dictionary(grouping: studentData.notes, by: { note -> String in
            note.tagsArray.first.map { TagHelper.tagName($0) } ?? "General"
        })
        var observationsSummary = ""
        for (tagName, notes) in notesByTag.sorted(by: { $0.key < $1.key }) {
            observationsSummary += "\n\(tagName) (\(notes.count) notes):\n"
            for note in notes.prefix(3) {
                observationsSummary += "  - \(note.body.prefix(100))\n"
            }
        }

        // Summarize practice patterns
        var practiceSummary = ""
        if !studentData.practiceSessions.isEmpty {
            let sessionsWithBreakthrough = studentData.practiceSessions.filter(\.madeBreakthrough).count
            let sessionsNeedingHelp = studentData.practiceSessions.filter(\.askedForHelp).count
            let sessionsHelpingPeers = studentData.practiceSessions.filter(\.helpedPeer).count
            let sessionsStruggling = studentData.practiceSessions.filter(\.struggledWithConcept).count

            practiceSummary = """
            - Breakthrough moments: \(sessionsWithBreakthrough)
            - Asked for help: \(sessionsNeedingHelp)
            - Helped peers: \(sessionsHelpingPeers)
            - Struggled with concept: \(sessionsStruggling)
            """
        }

        // Behavioral flags
        var behavioralFlags: [String] = []
        let readyForCheckIn = studentData.practiceSessions.filter(\.readyForCheckIn).count
        let readyForAssessment = studentData.practiceSessions.filter(\.readyForAssessment).count
        let needsReteaching = studentData.practiceSessions.filter(\.needsReteaching).count

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

    // Deprecated SwiftData bridge overloads removed - typealiases now point to CD types directly.

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
    let student: CDStudent
    let notes: [CDNote]
    let practiceSessions: [CDPracticeSession]
    let workCompletions: [CDWorkCompletionRecord]
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
