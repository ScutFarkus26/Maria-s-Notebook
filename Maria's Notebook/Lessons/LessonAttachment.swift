import Foundation
import SwiftData

/// Represents a file attachment (PDF, Pages, etc.) associated with a lesson.
/// Attachments can have different scopes: lesson-specific, group-wide, or subject-wide.
@Model
final class LessonAttachment: Identifiable {
    /// Stable identifier
    var id: UUID = UUID()
    
    /// Display name for the attachment
    var fileName: String = ""
    
    /// File bookmark for secure access (stored as external data for CloudKit)
    @Attribute(.externalStorage) var fileBookmark: Data? = nil
    
    /// Relative path to the file in the managed container
    var fileRelativePath: String = ""
    
    /// Date when the attachment was added
    var attachedAt: Date = Date()
    
    /// File type extension (e.g., "pdf", "pages")
    var fileType: String = ""
    
    /// File size in bytes
    var fileSizeBytes: Int64 = 0
    
    /// Scope of attachment: lesson-specific, group-wide, or subject-wide
    var scopeRaw: String = "lesson"
    
    /// Optional notes or description for the attachment
    var notes: String = ""
    
    /// Thumbnail data for preview (stored as external data for CloudKit)
    @Attribute(.externalStorage) var thumbnailData: Data? = nil
    
    // MARK: - Relationships
    
    /// The lesson this attachment belongs to (required)
    @Relationship var lesson: Lesson?
    
    // MARK: - Computed Properties
    
    @Transient
    var scope: AttachmentScope {
        get { AttachmentScope(rawValue: scopeRaw) ?? .lesson }
        set { scopeRaw = newValue.rawValue }
    }
    
    /// Human-readable file size
    @Transient
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
    
    /// Whether this attachment is inherited (group or subject scope)
    @Transient
    var isInherited: Bool {
        scope != .lesson
    }
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        fileName: String = "",
        fileBookmark: Data? = nil,
        fileRelativePath: String = "",
        attachedAt: Date = Date(),
        fileType: String = "",
        fileSizeBytes: Int64 = 0,
        scope: AttachmentScope = .lesson,
        notes: String = "",
        thumbnailData: Data? = nil,
        lesson: Lesson? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileBookmark = fileBookmark
        self.fileRelativePath = fileRelativePath
        self.attachedAt = attachedAt
        self.fileType = fileType
        self.fileSizeBytes = fileSizeBytes
        self.scopeRaw = scope.rawValue
        self.notes = notes
        self.thumbnailData = thumbnailData
        self.lesson = lesson
    }
}

// MARK: - AttachmentScope Enum

/// Defines the visibility scope of an attachment
public enum AttachmentScope: String, Codable, CaseIterable, Hashable, Identifiable {
    /// Attachment is specific to this lesson only
    case lesson
    /// Attachment is shared across all lessons in the same group
    case group
    /// Attachment is shared across all lessons in the same subject
    case subject
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .lesson: return "This Lesson"
        case .group: return "All Lessons in Group"
        case .subject: return "All Lessons in Subject"
        }
    }
    
    public var icon: String {
        switch self {
        case .lesson: return "doc"
        case .group: return "folder"
        case .subject: return "books.vertical"
        }
    }
    
    public var description: String {
        switch self {
        case .lesson: return "Only visible in this lesson"
        case .group: return "Visible in all lessons in this group"
        case .subject: return "Visible in all lessons in this subject"
        }
    }
}
