import Foundation
import CoreData

@objc(LessonAttachment)
public class CDLessonAttachment: NSManagedObject {
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
    @NSManaged public var lesson: CDLesson?

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

// MARK: - Computed Properties

extension CDLessonAttachment {
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
