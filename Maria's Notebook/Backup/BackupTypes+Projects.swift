import Foundation

// MARK: - CDProject DTOs

public struct ProjectDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var bookTitle: String?
    public var memberStudentIDs: [String]
}

public struct ProjectAssignmentTemplateDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var title: String
    public var instructions: String
    public var isShared: Bool
    public var defaultLinkedLessonID: String?
}

public struct ProjectSessionDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var meetingDate: Date
    public var chapterOrPages: String?
    public var agendaItemsJSON: String
    public var templateWeekID: UUID?
}

public struct ProjectRoleDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var title: String
    public var summary: String
    public var instructions: String
}

public struct ProjectTemplateWeekDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var weekIndex: Int
    public var readingRange: String
    public var agendaItemsJSON: String
    public var linkedLessonIDsJSON: String
    public var workInstructions: String
}

public struct ProjectWeekRoleAssignmentDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var weekID: UUID
    public var studentID: String
    public var roleID: UUID
}
