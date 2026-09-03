import Foundation

// MARK: - CDProject DTOs

nonisolated public struct ProjectDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var bookTitle: String?
    public var memberStudentIDs: [String]
    public var isActive: Bool?
    /// Conflict-resolution timestamp, preserved so post-restore deduplication
    /// doesn't treat every restored project as "just modified". Optional for
    /// compatibility with older backups that predate this field.
    public var modifiedAt: Date?
}

nonisolated public struct ProjectAssignmentTemplateDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var title: String
    public var instructions: String
    public var isShared: Bool
    public var defaultLinkedLessonID: String?
}

nonisolated public struct ProjectSessionDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var meetingDate: Date
    public var chapterOrPages: String?
    public var agendaItemsJSON: String
    public var templateWeekID: UUID?
    public var assignmentModeRaw: String?
    public var minSelections: Int?
    public var maxSelections: Int?
}

nonisolated public struct ProjectRoleDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var title: String
    public var summary: String
    public var instructions: String
}

nonisolated public struct ProjectTemplateWeekDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var weekIndex: Int
    public var readingRange: String
    public var agendaItemsJSON: String
    public var linkedLessonIDsJSON: String
    public var workInstructions: String
}

nonisolated public struct ProjectWeekRoleAssignmentDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var weekID: UUID
    public var studentID: String
    public var roleID: UUID
}
