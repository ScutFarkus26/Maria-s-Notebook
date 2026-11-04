import Foundation

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
