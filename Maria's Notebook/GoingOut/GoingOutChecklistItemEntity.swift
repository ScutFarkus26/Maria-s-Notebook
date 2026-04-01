import Foundation
import CoreData

@objc(CDGoingOutChecklistItem)
public class CDGoingOutChecklistItem: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var goingOutID: String
    @NSManaged public var title: String
    @NSManaged public var isCompleted: Bool
    @NSManaged public var sortOrder: Int64
    @NSManaged public var assignedToStudentID: String?

    // MARK: - Relationships
    @NSManaged public var goingOut: CDGoingOut?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "GoingOutChecklistItem", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.goingOutID = ""
        self.title = ""
        self.isCompleted = false
        self.sortOrder = 0
        self.assignedToStudentID = nil
    }
}
