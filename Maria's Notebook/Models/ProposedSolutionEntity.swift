import Foundation
import CoreData

@objc(ProposedSolutionEntity)
public class CDProposedSolutionEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var details: String
    @NSManaged public var proposedBy: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var isAdopted: Bool

    // MARK: - Relationships
    @NSManaged public var topic: CDCommunityTopicEntity?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ProposedSolution", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.details = ""
        self.proposedBy = ""
        self.createdAt = Date()
        self.isAdopted = false
    }
}
