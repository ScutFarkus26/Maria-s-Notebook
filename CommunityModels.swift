import Foundation
import SwiftData

/// A topic for Community Meetings that tracks an issue, proposed solutions, resolution, and notes.
@Model
final class CommunityTopic: Identifiable {
    // Identity
    var id: UUID

    // Core info
    var title: String
    var issueDescription: String

    // Timeline
    var createdAt: Date
    /// Set when the topic is addressed/resolved in a meeting
    var addressedDate: Date?

    // Resolution summary (freeform)
    var resolution: String
    /// Optional person who brought this topic forward
    var broughtBy: String = ""
    // Preferred name in UI: "Raised by". Keep storage in broughtBy for persistence.
    var raisedBy: String {
        get { broughtBy }
        set { broughtBy = newValue }
    }

    // Children
    @Relationship(deleteRule: .cascade, inverse: \ProposedSolution.topic) var proposedSolutions: [ProposedSolution] = []
    @Relationship(deleteRule: .cascade, inverse: \MeetingNote.topic) var notes: [MeetingNote] = []

    /// Freeform tags for filtering (e.g., Safety, Environment, Curriculum)
    var tags: [String] = []

    /// Attachments associated with this topic (photos, documents)
    @Relationship(deleteRule: .cascade, inverse: \CommunityAttachment.topic) var attachments: [CommunityAttachment] = []

    init(
        id: UUID = UUID(),
        title: String = "",
        issueDescription: String = "",
        createdAt: Date = Date(),
        addressedDate: Date? = nil,
        resolution: String = ""
    ) {
        self.id = id
        self.title = title
        self.issueDescription = issueDescription
        self.createdAt = createdAt
        self.addressedDate = addressedDate
        self.resolution = resolution
    }

    var isResolved: Bool { addressedDate != nil }
}

/// A proposed solution for a community topic.
@Model
final class ProposedSolution: Identifiable {
    var id: UUID
    var title: String
    var details: String
    /// Optional person who proposed this solution
    var proposedBy: String
    var createdAt: Date
    /// Whether this solution was adopted as part of the resolution
    var isAdopted: Bool

    // Parent
    var topic: CommunityTopic?

    init(
        id: UUID = UUID(),
        title: String = "",
        details: String = "",
        proposedBy: String = "",
        createdAt: Date = Date(),
        isAdopted: Bool = false,
        topic: CommunityTopic? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.proposedBy = proposedBy
        self.createdAt = createdAt
        self.isAdopted = isAdopted
        self.topic = topic
    }
}

/// A note captured during a community meeting, with an optional speaker attribution.
@Model
final class MeetingNote: Identifiable {
    var id: UUID
    var speaker: String
    var content: String
    var createdAt: Date

    // Parent
    var topic: CommunityTopic?

    init(
        id: UUID = UUID(),
        speaker: String = "",
        content: String = "",
        createdAt: Date = Date(),
        topic: CommunityTopic? = nil
    ) {
        self.id = id
        self.speaker = speaker
        self.content = content
        self.createdAt = createdAt
        self.topic = topic
    }
}
/// Binary attachment (photo or file) associated with a community topic.
@Model
final class CommunityAttachment: Identifiable {
    enum Kind: String, Codable, CaseIterable { case photo, file }

    var id: UUID
    var filename: String
    var kindRaw: String
    @Attribute(.externalStorage) var data: Data?
    var createdAt: Date

    // Parent
    var topic: CommunityTopic?

    init(
        id: UUID = UUID(),
        filename: String = "",
        kind: Kind = .file,
        data: Data? = nil,
        createdAt: Date = Date(),
        topic: CommunityTopic? = nil
    ) {
        self.id = id
        self.filename = filename
        self.kindRaw = kind.rawValue
        self.data = data
        self.createdAt = createdAt
        self.topic = topic
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .file }
        set { kindRaw = newValue.rawValue }
    }
}

