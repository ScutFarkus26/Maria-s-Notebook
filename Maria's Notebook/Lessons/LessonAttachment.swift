import Foundation

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
