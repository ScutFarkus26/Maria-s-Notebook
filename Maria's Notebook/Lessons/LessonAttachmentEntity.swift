import Foundation
import CoreData

@objc(LessonAttachment)
public class LessonAttachment: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var fileName: String
    @NSManaged public var fileBookmark: Data?
    @NSManaged public var fileRelativePath: String
    @NSManaged public var attachedAt: Date?
    @NSManaged public var fileType: String
    @NSManaged public var fileSizeBytes: Int64
    @NSManaged public var scopeRaw: String
    @NSManaged public var notes: String
    @NSManaged public var thumbnailData: Data?

    // MARK: - Relationships
    @NSManaged public var lesson: Lesson?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LessonAttachment", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.fileName = ""
        self.fileBookmark = nil
        self.fileRelativePath = ""
        self.attachedAt = Date()
        self.fileType = ""
        self.fileSizeBytes = 0
        self.scopeRaw = AttachmentScope.lesson.rawValue
        self.notes = ""
        self.thumbnailData = nil
    }
}

// MARK: - AttachmentScope Enum

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

// MARK: - Computed Properties

extension LessonAttachment {
    var scope: AttachmentScope {
        get { AttachmentScope(rawValue: scopeRaw) ?? .lesson }
        set { scopeRaw = newValue.rawValue }
    }

    /// Human-readable file size
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    /// Whether this attachment is inherited (group or subject scope)
    var isInherited: Bool {
        scope != .lesson
    }
}
