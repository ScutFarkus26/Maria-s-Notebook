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
}

nonisolated public struct TodoTemplateDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var title: String
    public var notes: String
    public var createdAt: Date
    public var priorityRaw: String
    public var defaultEstimatedMinutes: Int?
    public var defaultStudentIDs: [String]
    public var useCount: Int
    public var tags: [String]?
}

// MARK: - CDTrackEntity DTOs

nonisolated public struct SequenceTrackDTO: Codable, Sendable {
    public var id: UUID
    public var area: String
    public var sequence: String
    public var isSequential: Bool
    public var isExplicitlyDisabled: Bool
    public var createdAt: Date
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

// MARK: - CDSupply DTOs

nonisolated public struct SupplyDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var categoryRaw: String
    public var location: String
    public var currentQuantity: Int
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date
    // Restock (format v37+); absent in older backups, whose staples keep the
    // model's defaults and get levels from their counts after the restore.
    public var minimumThreshold: Int?
    public var unit: String?
    public var levelRaw: String?
    public var sourceRaw: String?
    public var urlString: String?
    public var levelChangedAt: Date?
    public var levelChangedByID: String?
    public var levelChangedByName: String?
}

// MARK: - CDDocument DTO

nonisolated public struct DocumentDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var category: String
    public var uploadDate: Date
    public var studentID: UUID?
    // PDF data excluded by design - too large for JSON backup
    /// Managed relative path only (the PDF payload itself is excluded).
    /// Optional for compatibility with older backups that predate this field.
    public var pdfFileRelativePath: String?
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

// MARK: - Scheduled Meeting DTO (format v12+)

nonisolated public struct ScheduledMeetingDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var date: Date
    public var createdAt: Date
    public var participantIDsData: Data?
    public var workID: String?
    public var isGroupMeeting: Bool?
    /// Format v24+: what the meeting is about.
    public var purpose: String?
}
