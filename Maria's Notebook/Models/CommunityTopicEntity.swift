import Foundation
import CoreData
import OSLog

@objc(CommunityTopicEntity)
public class CDCommunityTopicEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var issueDescription: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var addressedDate: Date?
    @NSManaged public var resolution: String
    @NSManaged public var broughtBy: String
    // Tags stored as Binary (_tagsData in xcdatamodeld)
    @NSManaged public var _tagsData: Data?

    // MARK: - Relationships
    @NSManaged public var proposedSolutions: NSSet?
    @NSManaged public var attachments: NSSet?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "CommunityTopic", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.issueDescription = ""
        self.createdAt = Date()
        self.addressedDate = nil
        self.resolution = ""
        self.broughtBy = ""
        self._tagsData = try? JSONEncoder().encode([String]())
    }
}

// MARK: - Computed Properties
extension CDCommunityTopicEntity {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MariasNotebook", category: "CommunityTopicEntity")

    /// Alias for broughtBy (preferred UI name)
    var raisedBy: String {
        get { broughtBy }
        set { broughtBy = newValue }
    }

    /// Freeform tags for filtering (e.g., Safety, Environment, Curriculum)
    /// Uses JSON encoding to safely handle corrupted data.
    var tags: [String] {
        get {
            guard let data = _tagsData else { return [] }
            do {
                return try JSONDecoder().decode([String].self, from: data)
            } catch {
                Self.logger.warning("Failed to decode tags: \(error.localizedDescription)")
                return []
            }
        }
        set {
            do {
                _tagsData = try JSONEncoder().encode(newValue)
            } catch {
                Self.logger.warning("Failed to encode tags: \(error.localizedDescription)")
                _tagsData = nil
            }
        }
    }

    var isResolved: Bool { addressedDate != nil }

    /// Cross-store inverse: fetches Notes whose communityTopicID matches this topic.
    var unifiedNotes: [CDNote] {
        guard let id, let ctx = managedObjectContext else { return [] }
        let req = CDFetchRequest(CDNote.self)
        req.predicate = NSPredicate(format: "communityTopicID == %@", id.uuidString)
        return (try? ctx.fetch(req)) ?? []
    }
}

// MARK: - Generated Accessors for proposedSolutions
extension CDCommunityTopicEntity {
    @objc(addProposedSolutionsObject:)
    @NSManaged public func addToProposedSolutions(_ value: CDProposedSolutionEntity)

    @objc(removeProposedSolutionsObject:)
    @NSManaged public func removeFromProposedSolutions(_ value: CDProposedSolutionEntity)

    @objc(addProposedSolutions:)
    @NSManaged public func addToProposedSolutions(_ values: NSSet)

    @objc(removeProposedSolutions:)
    @NSManaged public func removeFromProposedSolutions(_ values: NSSet)
}

// MARK: - Generated Accessors for attachments
extension CDCommunityTopicEntity {
    @objc(addAttachmentsObject:)
    @NSManaged public func addToAttachments(_ value: CDCommunityAttachmentEntity)

    @objc(removeAttachmentsObject:)
    @NSManaged public func removeFromAttachments(_ value: CDCommunityAttachmentEntity)

    @objc(addAttachments:)
    @NSManaged public func addToAttachments(_ values: NSSet)

    @objc(removeAttachments:)
    @NSManaged public func removeFromAttachments(_ values: NSSet)
}
