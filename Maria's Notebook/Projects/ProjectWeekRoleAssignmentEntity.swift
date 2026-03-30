import Foundation
import CoreData

@objc(ProjectWeekRoleAssignment)
public class CDProjectWeekRoleAssignment: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var weekID: String
    @NSManaged public var studentID: String
    @NSManaged public var roleID: String

    // MARK: - Relationships
    @NSManaged public var week: CDProjectTemplateWeek?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ProjectWeekRoleAssignment", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.weekID = ""
        self.studentID = ""
        self.roleID = ""
    }
}

// MARK: - Computed Properties

extension CDProjectWeekRoleAssignment {
    var weekIDUUID: UUID? {
        get { UUID(uuidString: weekID) }
        set { weekID = newValue?.uuidString ?? "" }
    }

    var roleIDUUID: UUID? {
        get { UUID(uuidString: roleID) }
        set { roleID = newValue?.uuidString ?? "" }
    }
}
