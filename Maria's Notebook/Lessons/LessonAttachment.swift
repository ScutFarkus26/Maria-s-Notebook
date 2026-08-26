import Foundation

// MARK: - AttachmentScope Enum

/// Defines the visibility scope of an attachment
public enum AttachmentScope: String, Codable, CaseIterable, Hashable, Identifiable {
    /// Attachment is specific to this lesson only
    case lesson
    /// Attachment is shared across all lessons in the same sequence
    case sequence
    /// Attachment is shared across all lessons in the same area
    case area

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lesson: return "This Lesson"
        case .sequence: return "All Lessons in Sequence"
        case .area: return "All Lessons in Area"
        }
    }

    public var icon: String {
        switch self {
        case .lesson: return "doc"
        case .sequence: return "folder"
        case .area: return "books.vertical"
        }
    }

    public var description: String {
        switch self {
        case .lesson: return "Only visible in this lesson"
        case .sequence: return "Visible in all lessons in this sequence"
        case .area: return "Visible in all lessons in this area"
        }
    }
}
