import Foundation
import CoreData

// Deprecated: Entity kept as stub for CloudKit schema compatibility.
// Do not add new code here.

@objc(CDProjectAssignmentTemplate)
public class CDProjectAssignmentTemplate: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var projectID: String
    @NSManaged public var title: String
    @NSManaged public var instructions: String
    @NSManaged public var isShared: Bool
    @NSManaged public var defaultLinkedLessonID: String?
    @NSManaged public var project: CDProject?
}
