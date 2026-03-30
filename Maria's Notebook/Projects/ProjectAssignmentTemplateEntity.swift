import Foundation
import CoreData

@objc(ProjectAssignmentTemplate)
public class ProjectAssignmentTemplate: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var projectID: String
    @NSManaged public var title: String
    @NSManaged public var instructions: String
    @NSManaged public var isShared: Bool
    @NSManaged public var defaultLinkedLessonID: String?

    // MARK: - Relationships
    @NSManaged public var project: Project?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ProjectAssignmentTemplate", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.projectID = ""
        self.title = ""
        self.instructions = ""
        self.isShared = true
        self.defaultLinkedLessonID = nil
    }
}

// MARK: - Computed Properties

extension ProjectAssignmentTemplate {
    var projectIDUUID: UUID? {
        get { UUID(uuidString: projectID) }
        set { projectID = newValue?.uuidString ?? "" }
    }
}
