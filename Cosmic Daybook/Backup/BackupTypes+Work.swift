import Foundation

// MARK: - Work DTOs

/// Modern DTO that captures all CDWorkModel fields (format v11+).
nonisolated public struct WorkModelDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var workTypeRaw: String
    public var studentLessonID: UUID?
    public var createdAt: Date
    public var completedAt: Date?
    // Modern work tracking
    public var kindRaw: String?
    public var statusRaw: String
    public var assignedAt: Date
    public var lastTouchedAt: Date?
    public var dueAt: Date?
    public var completionOutcomeRaw: String?
    // CloudKit-compatible string FKs
    public var studentID: String
    public var lessonID: String
    public var presentationID: String?
    public var trackID: String?
    public var trackStepID: String?
    public var scheduledNote: String?
    public var scheduledReasonRaw: String?
    public var sourceContextTypeRaw: String?
    public var sourceContextID: String?
    public var sampleWorkID: String?
    public var checkInStyleRaw: String?
    // Format v14+
    public var restingUntil: Date?
}

// MARK: - CDPlanningRecommendation DTO

nonisolated public struct PlanningRecommendationDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var lessonID: String
    public var studentIDsData: Data?
    public var reasoning: String
    public var confidence: Double
    public var priority: Int
    public var subjectContext: String
    public var groupContext: String
    public var planningSessionID: String
    public var depthLevel: String
    public var decisionRaw: String?
    public var decisionAt: Date?
    public var teacherNote: String?
    public var outcomeRaw: String?
    public var outcomeRecordedAt: Date?
    public var presentationID: String?
}

// MARK: - CDResource DTO

nonisolated public struct ResourceDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var descriptionText: String
    public var categoryRaw: String
    public var fileRelativePath: String
    public var fileSizeBytes: Int64
    public var tags: [String]
    public var isFavorite: Bool
    public var lastViewedAt: Date?
    public var linkedLessonIDs: String
    public var linkedAreas: String
    public var createdAt: Date
    public var modifiedAt: Date
    // CDNote: fileBookmark and thumbnailData are @externalStorage and excluded from backups by design
}

// MARK: - CDNoteStudentLink DTO

nonisolated public struct WorkCheckInDTO: Codable, Sendable {
    public var id: UUID
    public var workID: String
    public var date: Date
    public var statusRaw: String
    public var purpose: String
    public var studentInitiated: Bool?
    /// How long the practice lasted (schema 23; absent in older backups).
    public var durationMinutes: Int?
}

nonisolated public struct WorkParticipantEntityDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var completedAt: Date?
    public var workID: UUID?
}

nonisolated public struct WorkCompletionRecordDTO: Codable, Sendable {
    public var id: UUID
    public var workID: UUID
    public var studentID: UUID
    public var completedAt: Date
}
