import Foundation
import CoreData

// Deprecated: Entity kept as stub for CloudKit schema compatibility.
// Do not add new code here.

@objc(CDProjectTemplateWeek)
public class CDProjectTemplateWeek: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var projectID: String
    @NSManaged public var weekIndex: Int64
    @NSManaged public var readingRange: String
    @NSManaged public var agendaItemsJSON: String
    @NSManaged public var linkedLessonIDsJSON: String
    @NSManaged public var workInstructions: String
    @NSManaged public var assignmentModeRaw: String
    @NSManaged public var minSelections: Int64
    @NSManaged public var maxSelections: Int64
    @NSManaged public var offeredWorksJSON: String
    @NSManaged public var roleAssignments: NSSet?
}
