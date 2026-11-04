import Foundation

// MARK: - Core DTOs (calendar days and community topics)

nonisolated public struct ItemDTO: Codable, Sendable {
    public var id: UUID
    public var timestamp: Date
}

nonisolated public struct NonSchoolDayDTO: Codable, Sendable {
    public var id: UUID
    public var date: Date
    public var reason: String?
}

nonisolated public struct SchoolDayOverrideDTO: Codable, Sendable {
    public var id: UUID
    public var date: Date
}

nonisolated public struct CommunityTopicDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var issueDescription: String
    public var createdAt: Date
    public var addressedDate: Date?
    public var resolution: String
    public var raisedBy: String
    public var tags: [String]
}

nonisolated public struct CommunityAttachmentDTO: Codable, Sendable {
    public var id: UUID
    public var topicID: UUID?
    public var filename: String
    public var kind: String
    // Do not include raw data; metadata only
    public var createdAt: Date
}

// MARK: - Template DTOs
