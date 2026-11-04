import Foundation

// MARK: - Todo DTOs

nonisolated public struct TodoItemDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var completedAt: Date?
    public var orderIndex: Int
    public var dueDate: Date?
    public var priorityRaw: String
    public var recurrenceRaw: String
    public var studentIDs: [String]
    public var linkedWorkItemID: String?
    public var attachmentPaths: [String]
    public var estimatedMinutes: Int?
    public var actualMinutes: Int?
    public var reminderDate: Date?
    public var reflectionNotes: String
    public var tags: [String]
    // CDSchedule fields
    public var scheduledDate: Date?
    public var isSomeday: Bool?
    public var repeatAfterCompletion: Bool?
    public var customIntervalDays: Int?
    // Location fields
    public var locationName: String?
    public var locationLatitude: Double?
    public var locationLongitude: Double?
    public var locationRadius: Double
    public var notifyOnEntry: Bool
    public var notifyOnExit: Bool
    public var moodRaw: String?
    /// The Tide action it is shared with (v41, schema 19); absent before.
    public var tideLink: String?
}

// MARK: - Development Snapshot DTO

nonisolated public struct DevelopmentSnapshotDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var generatedAt: Date
    public var lookbackDays: Int
    public var analysisVersion: String
    public var overallProgress: String
    public var keyStrengths: [String]
    public var areasForGrowth: [String]
    public var developmentalMilestones: [String]
    public var observedPatterns: [String]
    public var behavioralTrends: [String]
    public var socialEmotionalInsights: [String]
    public var recommendedNextLessons: [String]
    public var suggestedPracticeFocus: [String]
    public var interventionSuggestions: [String]
    public var totalNotesAnalyzed: Int
    public var practiceSessionsAnalyzed: Int
    public var workCompletionsAnalyzed: Int
    public var averagePracticeQuality: Double?
    public var independenceLevel: Double?
    public var rawAnalysisJSON: String
    public var userNotes: String
    public var isReviewed: Bool
    public var sharedWithParents: Bool
    public var sharedAt: Date?
}

// MARK: - Agenda Order DTO

nonisolated public struct TodayAgendaOrderDTO: Codable, Sendable {
    public var id: UUID
    public var day: Date
    public var itemTypeRaw: String
    public var itemID: UUID
    public var position: Int
}

// MARK: - Going Out DTOs (format v12+)

nonisolated public struct GoingOutChecklistItemDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var goingOutID: String
    public var title: String
    public var isCompleted: Bool
    public var sortOrder: Int
    public var assignedToStudentID: String?
}
