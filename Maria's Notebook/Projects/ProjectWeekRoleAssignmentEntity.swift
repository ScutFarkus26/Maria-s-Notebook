import Foundation
import CoreData

// Deprecated: Entity kept as stub for CloudKit schema compatibility.
// Do not add new code here.

@objc(CDProjectWeekRoleAssignment)
public class CDProjectWeekRoleAssignment: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var weekID: String
    @NSManaged public var studentID: String
    @NSManaged public var roleID: String
    @NSManaged public var week: CDProjectTemplateWeek?
}
