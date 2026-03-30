import Foundation
import CoreData

@objc(CommunityAttachmentEntity)
public class CommunityAttachmentEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var filename: String
    @NSManaged public var kindRaw: String
    @NSManaged public var data: Data?
    @NSManaged public var createdAt: Date?

    // MARK: - Relationships
    @NSManaged public var topic: CommunityTopicEntity?

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
extension CommunityAttachmentEntity {
    /// Kind enum matching the original SwiftData model
    enum Kind: String, Codable, CaseIterable {
        case photo, file
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .file }
        set { kindRaw = newValue.rawValue }
    }
}
