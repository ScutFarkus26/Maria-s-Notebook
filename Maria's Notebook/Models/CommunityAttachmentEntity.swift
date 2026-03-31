import Foundation
import CoreData

@objc(CommunityAttachmentEntity)
public class CDCommunityAttachmentEntity: NSManagedObject {
    // MARK: - Type Aliases (enums defined in SwiftData models)
    typealias Kind = CommunityAttachmentKind

    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var filename: String
    @NSManaged public var kindRaw: String
    @NSManaged public var data: Data?
    @NSManaged public var createdAt: Date?

    // MARK: - Relationships
    @NSManaged public var topic: CDCommunityTopicEntity?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "CommunityAttachment", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.filename = ""
        self.kindRaw = Kind.file.rawValue
        self.data = nil
        self.createdAt = Date()
    }
}

// MARK: - Computed Properties & Enums
extension CDCommunityAttachmentEntity {
    /// Kind enum matching the original SwiftData model

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .file }
        set { kindRaw = newValue.rawValue }
    }
}
