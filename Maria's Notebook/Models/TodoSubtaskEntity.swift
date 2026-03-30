import Foundation
import CoreData

@objc(TodoSubtaskEntity)
public class CDTodoSubtaskEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var isCompleted: Bool
    @NSManaged public var orderIndex: Int64
    @NSManaged public var createdAt: Date?
    @NSManaged public var completedAt: Date?

    // MARK: - Relationships
    @NSManaged public var todo: CDTodoItemEntity?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TodoSubtask", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.isCompleted = false
        self.orderIndex = 0
        self.createdAt = Date()
        self.completedAt = nil
    }
}
