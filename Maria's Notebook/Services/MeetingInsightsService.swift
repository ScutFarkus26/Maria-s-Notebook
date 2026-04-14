import Foundation
import CoreData
import OSLog

// MARK: - Meeting Insights Result

struct MeetingInsightsResult: Sendable {
    let progressSummary: String
    let sentiment: MeetingSentiment
    let progressTrends: [String]
    let regressionSignals: [String]
    let neglectedAreas: [String]
    let actionItems: [String]
    let analyzedMeetingCount: Int
    let timeframeDescription: String
}

enum MeetingSentiment: String, Sendable {
    case confident
    case progressing
    case mixed
    case struggling
    case insufficient

    var icon: String {
        switch self {
        case .confident: "sun.max.fill"
        case .progressing: "sun.min.fill"
        case .mixed: "cloud.sun.fill"
        case .struggling: "cloud.rain.fill"
        case .insufficient: "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .confident: "Confident"
        case .progressing: "Progressing"
        case .mixed: "Mixed"
        case .struggling: "Struggling"
        case .insufficient: "Not enough data"
        }
    }

    var color: String {
        switch self {
        case .confident: "green"
        case .progressing: "blue"
        case .mixed: "orange"
        case .struggling: "red"
        case .insufficient: "gray"
        }
    }
}

// MARK: - Meeting Insights Service

@MainActor
final class MeetingInsightsService {
    private static let logger = Logger.ai

    private let modelContext: NSManagedObjectContext
    private let mcpClient: MCPClientProtocol

    init(modelContext: NSManagedObjectContext, mcpClient: MCPClientProtocol) {
        self.modelContext = modelContext
        self.mcpClient = mcpClient
    }

    // MARK: - Public API

    func analyzeMeetings(
        for student: CDStudent,
        meetings: [CDStudentMeeting],
        workModels: [CDWorkModel],
        lessonAssignments: [CDLessonAssignment],
        timeframeDays: Int
    ) async throws -> MeetingInsightsResult {
        mcpClient.configureForFeature(.backgroundTasks)

        let cutoff = Calendar.current.date(byAdding: .day, value: -timeframeDays, to: Date()) ?? Date()
        let relevantMeetings = meetings.filter { ($0.date ?? .distantPast) >= cutoff }

        guard !relevantMeetings.isEmpty else {
            return MeetingInsightsResult(
                progressSummary: "No meetings found in this timeframe.",
                sentiment: .insufficient,
                progressTrends: [],
                regressionSignals: [],
                neglectedAreas: [],
                actionItems: [],
                analyzedMeetingCount: 0,
                timeframeDescription: timeframeLabel(timeframeDays)
            )
        }

        // Extract Sendable data from managed objects before async boundary
        let meetingData = relevantMeetings.map { MeetingSnapshot(from: $0) }
        let workSnapshot = WorkContextSnapshot(
            openCount: workModels.filter { !$0.isCompleted }.count,
            overdueCount: workModels.filter {
                !$0.isCompleted && ($0.createdAt ?? Date()).timeIntervalSinceNow < -Double(14 * 86_400)
            }.count,
            recentCompletedCount: workModels.filter {
                $0.isCompleted && ($0.completedAt ?? .distantPast).timeIntervalSinceNow > -Double(7 * 86_400)
            }.count
        )
        let lessonNames = lessonAssignments.compactMap { $0.lesson?.name ?? "Unknown Lesson" }
        let studentName = student.fullName
        let studentAge = student.birthday?.age ?? 0
        let studentLevel = student.level.rawValue

        let prompt = buildPrompt(
            studentName: studentName,
            studentAge: studentAge,
            studentLevel: studentLevel,
            meetings: meetingData,
            workSnapshot: workSnapshot,
            lessonNames: lessonNames,
            timeframeDays: timeframeDays
        )

        let response = try await mcpClient.generateStructuredJSON(
            prompt: prompt,
            systemMessage: """
            You are an experienced Montessori guide assistant analyzing student meeting patterns. \
            Provide structured, actionable insights based on meeting notes over time. \
            Focus on identifying progress, areas needing attention, and concrete next steps. \
            Use Montessori-appropriate language and a growth mindset perspective.
            """,
            temperature: 0.3,
            maxTokens: 2048
        )

        return try parseResponse(json: response, meetingCount: relevantMeetings.count, timeframeDays: timeframeDays)
    }

    // MARK: - Private Helpers

    private func buildPrompt(
        studentName: String,
        studentAge: Int,
        studentLevel: String,
        meetings: [MeetingSnapshot],
        workSnapshot: WorkContextSnapshot,
        lessonNames: [String],
        timeframeDays: Int
    ) -> String {
        var meetingSummaries = ""
        for (index, meeting) in meetings.enumerated() {
            let dateStr = meeting.date.formatted(date: .abbreviated, time: .omitted)
            let completedStr = meeting.completed ? "Completed" : "Incomplete"
            meetingSummaries += """

            Meeting \(index + 1) (\(dateStr), \(completedStr)):
            """
            if !meeting.reflection.isEmpty {
                meetingSummaries += "\n  Reflection: \(meeting.reflection)"
            }
            if !meeting.focus.isEmpty {
                meetingSummaries += "\n  Focus: \(meeting.focus)"
            }
            if !meeting.requests.isEmpty {
                meetingSummaries += "\n  Requests: \(meeting.requests)"
            }
            if !meeting.guideNotes.isEmpty {
                meetingSummaries += "\n  Guide Notes: \(meeting.guideNotes)"
            }
        }

        let lessonContext = lessonNames.isEmpty
            ? "No recent lessons recorded"
            : lessonNames.prefix(15).joined(separator: ", ")

        return """
        Analyze the following \(meetings.count) student meetings from the last \(timeframeDays) days.

        Student: \(studentName) (Age: \(studentAge), Level: \(studentLevel))

        CURRENT WORK STATUS:
        - Open work items: \(workSnapshot.openCount)
        - Overdue items: \(workSnapshot.overdueCount)
        - Recently completed: \(workSnapshot.recentCompletedCount)

        RECENT LESSONS: \(lessonContext)

        MEETING NOTES:
        \(meetingSummaries)

        Respond with JSON in this exact format:
        {
            "progressSummary": "2-3 sentence overview of the student's trajectory across these meetings",
            "sentiment": "confident|progressing|mixed|struggling",
            "progressTrends": ["specific area of growth 1", "specific area of growth 2"],
            "regressionSignals": ["area of concern 1"],
            "neglectedAreas": ["curriculum area or skill not addressed recently"],
            "actionItems": ["specific action for the guide to take"]
        }

        Guidelines:
        - Be specific and reference actual meeting content
        - progressTrends: areas where clear growth or positive momentum is evident
        - regressionSignals: areas where the student may be stuck, regressing, or struggling
        - neglectedAreas: curriculum areas or skills not mentioned in meetings that may need attention
        - actionItems: concrete, actionable steps for the guide
        - Use "insufficient" for sentiment only if fewer than 2 meetings
        - Keep each array to 2-4 items maximum
        """
    }

    private func parseResponse(json: String, meetingCount: Int, timeframeDays: Int) throws -> MeetingInsightsResult {
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MeetingInsightsResponse.self, from: data)

        let sentiment = MeetingSentiment(rawValue: decoded.sentiment) ?? .mixed

        return MeetingInsightsResult(
            progressSummary: decoded.progressSummary,
            sentiment: sentiment,
            progressTrends: decoded.progressTrends,
            regressionSignals: decoded.regressionSignals,
            neglectedAreas: decoded.neglectedAreas,
            actionItems: decoded.actionItems,
            analyzedMeetingCount: meetingCount,
            timeframeDescription: timeframeLabel(timeframeDays)
        )
    }

    private func timeframeLabel(_ days: Int) -> String {
        switch days {
        case ...14: "2 weeks"
        case ...30: "1 month"
        case ...90: "3 months"
        case ...180: "6 months"
        default: "\(days) days"
        }
    }
}

// MARK: - Sendable Data Snapshots

private struct MeetingSnapshot: Sendable {
    let date: Date
    let completed: Bool
    let reflection: String
    let focus: String
    let requests: String
    let guideNotes: String

    init(from meeting: CDStudentMeeting) {
        self.date = meeting.date ?? Date()
        self.completed = meeting.completed
        self.reflection = meeting.reflection.trimmed()
        self.focus = meeting.focus.trimmed()
        self.requests = meeting.requests.trimmed()
        self.guideNotes = meeting.guideNotes.trimmed()
    }
}

private struct WorkContextSnapshot: Sendable {
    let openCount: Int
    let overdueCount: Int
    let recentCompletedCount: Int
}

// MARK: - JSON Response

private struct MeetingInsightsResponse: Decodable {
    let progressSummary: String
    let sentiment: String
    let progressTrends: [String]
    let regressionSignals: [String]
    let neglectedAreas: [String]
    let actionItems: [String]
}
