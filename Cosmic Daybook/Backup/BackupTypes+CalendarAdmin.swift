import Foundation

// MARK: - Calendar & Admin DTOs

nonisolated public struct ScheduleSlotDTO: Codable, Sendable {
    public var id: UUID
    public var scheduleID: String
    public var studentID: String
    public var weekdayRaw: String
    public var timeString: String?
    public var sortOrder: Int
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date
}

nonisolated public struct IssueDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var modifiedAt: Date
    public var title: String
    public var issueDescription: String
    public var categoryRaw: String
    public var priorityRaw: String
    public var statusRaw: String
    public var studentIDs: [String]
    public var location: String?
    public var resolvedAt: Date?
    public var resolutionSummary: String?
}

nonisolated public struct IssueActionDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var modifiedAt: Date
    public var issueID: String
    public var actionTypeRaw: String
    public var actionDescription: String
    public var actionDate: Date
    public var participantStudentIDs: [String]
    public var nextSteps: String?
    public var followUpRequired: Bool
    public var followUpDate: Date?
    public var followUpCompleted: Bool
}
