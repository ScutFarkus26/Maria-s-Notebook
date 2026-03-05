import Foundation

// MARK: - Calendar & Admin DTOs

public struct StudentMeetingDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: UUID
    public var date: Date
    public var completed: Bool
    public var reflection: String
    public var focus: String
    public var requests: String
    public var guideNotes: String
}

public struct ReminderDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var isCompleted: Bool
    public var completedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    // EventKit IDs excluded - device-specific
}

public struct CalendarEventDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var location: String?
    public var notes: String?
    public var isAllDay: Bool
    // EventKit IDs excluded - device-specific
}

public struct ScheduleDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var colorHex: String
    public var icon: String
    public var createdAt: Date
    public var modifiedAt: Date
}

public struct ScheduleSlotDTO: Codable, Sendable {
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

public struct IssueDTO: Codable, Sendable {
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

public struct IssueActionDTO: Codable, Sendable {
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

public struct ProcedureDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var content: String
    public var categoryRaw: String
    public var icon: String
    public var relatedProcedureIDs: [String]
    public var createdAt: Date
    public var modifiedAt: Date
}
