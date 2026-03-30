import Foundation
import CoreData

@objc(ProjectRole)
public class ProjectRole: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var projectID: String
    @NSManaged public var title: String
    @NSManaged public var summary: String
    @NSManaged public var instructions: String

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ProjectRole", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.projectID = ""
        self.title = ""
        self.summary = ""
        self.instructions = ""
    }
}

// MARK: - Computed Properties

extension ProjectRole {
    var projectIDUUID: UUID? {
        get { UUID(uuidString: projectID) }
        set { projectID = newValue?.uuidString ?? "" }
    }
}
