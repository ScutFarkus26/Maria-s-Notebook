//
//  StudentAnalysisService.swift
//  Cosmic Daybook
//
//  MCP-powered service for analyzing student development patterns and progress
//

import Foundation
import CoreData

/// Service that leverages MCP tools to analyze student data and provide actionable insights
final class StudentAnalysisService {

    // MARK: - Dependencies

    private let modelContext: NSManagedObjectContext
    private let mcpClient: MCPClientProtocol

    // MARK: - Initialization

    init(modelContext: NSManagedObjectContext, mcpClient: MCPClientProtocol) {
        self.modelContext = modelContext
        self.mcpClient = mcpClient
    }

    // MARK: - Public API

    /// Analyzes a student's recent activity and generates development insights
    /// - Parameters:
    ///   - student: The student to analyze
    ///   - lookbackDays: Number of days to analyze (default: 30)
    /// - Returns: A CDDevelopmentSnapshotEntity containing analysis results
    func analyzeStudent(_ student: CDStudent, lookbackDays: Int = 30) async throws -> CDDevelopmentSnapshotEntity {
        let cutoffDate = AppCalendar.shared.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()

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

        // Her notes: the ones about her alone, and the group observations that name
        // her among others (no single student in the index, so they're matched by
        // their scope; they used to be left out). Whole-class notes stay out.
        let noteRequest = CDFetchRequest(CDNote.self)
        noteRequest.predicate = NSPredicate(
            format: "createdAt >= %@ AND (searchIndexStudentID == %@ "
                + "OR (scopeIsAll == NO AND searchIndexStudentID == nil))",
            since as NSDate, studentID as CVarArg
        )
        noteRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let notes = ((try? modelContext.fetch(noteRequest)) ?? []).filter { note in
            note.searchIndexStudentID == studentID || note.scope.applies(to: studentID)
        }

        // Practice is a check-in on her work (`CDWorkCheckIn.isPractice`). Her
        // work ids are read as plain values, so no work row is materialized.
        let workIDRequest = NSFetchRequest<NSDictionary>(entityName: "WorkModel")
        workIDRequest.resultType = .dictionaryResultType
        workIDRequest.propertiesToFetch = ["id"]
        workIDRequest.predicate = NSPredicate(format: "studentID == %@", studentID.uuidString)
        let workIDs = try modelContext.fetch(workIDRequest).compactMap { ($0["id"] as? UUID)?.uuidString }
        let practiceRequest = CDFetchRequest(CDWorkCheckIn.self)
        practiceRequest.predicate = NSPredicate(
            format: "date >= %@ AND workID IN %@ AND (durationMinutes != nil OR purpose == %@)",
            since as NSDate, workIDs, PracticeCheckIns.purpose
        )
        practiceRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        let practice = try modelContext.fetch(practiceRequest)

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

        // The ratings are words on a practice check-in's note now, not
        // numbers, so there is no average to take.
        return StudentDataPackage(
            student: student,
            notes: notes,
            practiceSessions: practice,
            workCompletions: workCompletions,
            averagePracticeQuality: nil,
            averageIndependenceLevel: nil,
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
            let sessionsWithBreakthrough = studentData.practiceCount(.madeBreakthrough)
            let sessionsNeedingHelp = studentData.practiceCount(.askedForHelp)
            let sessionsHelpingPeers = studentData.practiceCount(.helpedPeer)
            let sessionsStruggling = studentData.practiceCount(.struggled)

            practiceSummary = """
            - Breakthrough moments: \(sessionsWithBreakthrough)
            - Asked for help: \(sessionsNeedingHelp)
            - Helped peers: \(sessionsHelpingPeers)
            - Struggled with concept: \(sessionsStruggling)
            """
        }

        // Behavioral flags
        var behavioralFlags: [String] = []
        let readyForCheckIn = studentData.practiceCount(.readyForCheckIn)
        let readyForAssessment = studentData.practiceCount(.readyForAssessment)
        let needsReteaching = studentData.practiceCount(.needsReteaching)

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
    let student: CDStudent
    let notes: [CDNote]
    /// Her practice check-ins in the window.
    let practiceSessions: [CDWorkCheckIn]
    let workCompletions: [CDWorkCompletionRecord]
    let averagePracticeQuality: Double?
    let averageIndependenceLevel: Double?
    let dateRange: ClosedRange<Date>

    /// How many of her practices carried `signal`.
    func practiceCount(_ signal: PracticeSignal) -> Int {
        practiceSessions.filter { $0.practiceSignals.contains(signal) }.count
    }
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
