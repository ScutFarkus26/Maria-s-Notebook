import Foundation

// MARK: - Retired project plans
// Payload fields no backed-up type fills; projects, their sessions and roles
// are table rows (ModelRowKinds+Projects.swift).

nonisolated public struct ProjectAssignmentTemplateDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var title: String
    public var instructions: String
    public var isShared: Bool
    public var defaultLinkedLessonID: String?
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
