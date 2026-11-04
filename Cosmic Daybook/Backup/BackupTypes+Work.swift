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
