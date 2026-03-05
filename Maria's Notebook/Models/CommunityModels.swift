import Foundation
import OSLog
import SwiftData

/// A topic for Community Meetings that tracks an issue, proposed solutions, resolution, and notes.
@Model
final class CommunityTopic: Identifiable {
    private static let logger = Logger.database

    // Identity
    var id: UUID = UUID()

    // Core info
    var title: String = ""
    var issueDescription: String = ""

    // Timeline
    var createdAt: Date = Date()
    /// Set when the topic is addressed/resolved in a meeting
    var addressedDate: Date?

    // Resolution summary (freeform)
    var resolution: String = ""
    /// Optional person who brought this topic forward
    var broughtBy: String = ""
    // Preferred name in UI: "Raised by". Keep storage in broughtBy for persistence.
    var raisedBy: String {
        get { broughtBy }
        set { broughtBy = newValue }
    }

    // Children
    // CloudKit compatibility: Relationship arrays must be optional
    @Relationship(deleteRule: .cascade, inverse: \ProposedSolution.topic)
    var proposedSolutions: [ProposedSolution]? = []
    // Inverse relationship for Note.communityTopic
    @Relationship(deleteRule: .cascade, inverse: \Note.communityTopic) var unifiedNotes: [Note]? = []

    /// Freeform tags for filtering (e.g., Safety, Environment, Curriculum)
    /// 
    /// MIGRATION NOTE: The old database had 'tags' as [String] but may contain corrupted UUID data.
    /// We now store tags as JSON-encoded Data in '_tagsData' to avoid SwiftData type conflicts.
    /// Using Data instead of String provides better type safety and avoids encoding issues.
    /// The public 'tags' property is computed and marked @Transient so SwiftData doesn't try
    /// to read the old stored property during fetches.
    @Attribute(.externalStorage) private var _tagsData: Data?
    
    /// Public tags property. Uses JSON encoding to safely handle corrupted data.
    /// Marked as @Transient so SwiftData ignores it completely and doesn't try to read
    /// any old stored property that may contain corrupted UUID data.
    /// 
    /// LAZY MIGRATION: When this property is accessed, it safely decodes from _tagsData.
    /// If _tagsData is nil (new record) or invalid (corrupted), it returns an empty array.
    /// When set, it encodes to _tagsData, which triggers a lazy migration on save.
    @Transient
    var tags: [String] {
        get {
            // Safely decode from JSON storage
            guard let data = _tagsData else {
                return []
            }
            do {
                let array = try JSONDecoder().decode([String].self, from: data)
                return array
            } catch {
                // If decoding fails (e.g., old corrupted data), return empty array
                // This prevents crashes and allows the record to be accessed safely
                Self.logger.warning("Failed to decode tags: \(error.localizedDescription)")
                return []
            }
        }
        set {
            // Encode to JSON for storage
            // This will persist the new format, completing the lazy migration
            do {
                let data = try JSONEncoder().encode(newValue)
                _tagsData = data
            } catch {
                // If encoding fails, store nil (will be treated as empty array on read)
                Self.logger.warning("Failed to encode tags: \(error.localizedDescription)")
                _tagsData = nil
            }
        }
    }

    /// Attachments associated with this topic (photos, documents)
    @Relationship(deleteRule: .cascade, inverse: \CommunityAttachment.topic)
    var attachments: [CommunityAttachment]? = []

    init(
        id: UUID = UUID(),
        title: String = "",
        issueDescription: String = "",
        createdAt: Date = Date(),
        addressedDate: Date? = nil,
        resolution: String = "",
        broughtBy: String = ""
    ) {
        self.id = id
        self.title = title
        self.issueDescription = issueDescription
        self.createdAt = createdAt
        self.addressedDate = addressedDate
        self.resolution = resolution
        self.broughtBy = broughtBy
        self.proposedSolutions = []
        self.unifiedNotes = []
        self.attachments = []
        do {
            self._tagsData = try JSONEncoder().encode([String]())
        } catch {
            Self.logger.warning("Failed to encode empty tags array: \(error.localizedDescription)")
            self._tagsData = nil
        }
    }

    var isResolved: Bool { addressedDate != nil }
}

/// A proposed solution for a community topic.
@Model
final class ProposedSolution: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    /// Optional person who proposed this solution
    var proposedBy: String = ""
    var createdAt: Date = Date()
    /// Whether this solution was adopted as part of the resolution
    var isAdopted: Bool = false

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

/// Binary attachment (photo or file) associated with a community topic.
@Model
final class CommunityAttachment: Identifiable {
    enum Kind: String, Codable, CaseIterable { case photo, file }

    var id: UUID = UUID()
    var filename: String = ""
    var kindRaw: String = Kind.file.rawValue
    @Attribute(.externalStorage) var data: Data?
    var createdAt: Date = Date()

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
