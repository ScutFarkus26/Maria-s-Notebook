import Foundation
import CoreData

@objc(TodoTemplateEntity)
public class CDTodoTemplateEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var title: String
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var priorityRaw: String
    @NSManaged public var defaultEstimatedMinutes: Int64
    // Transformable [String] arrays stored as NSObject? in Core Data
    @NSManaged public var defaultStudentIDs: NSObject?
    @NSManaged public var tags: NSObject?
    @NSManaged public var useCount: Int64

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TodoTemplate", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.name = ""
        self.title = ""
        self.notes = ""
        self.createdAt = Date()
        self.priorityRaw = TodoPriority.none.rawValue
        self.defaultEstimatedMinutes = 0
        self.defaultStudentIDs = nil
        self.tags = nil
        self.useCount = 0
    }
}

// MARK: - Computed Properties
extension CDTodoTemplateEntity {
    var priority: TodoPriority {
        get { TodoPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    /// Typed accessor for defaultStudentIDs Transformable
    var defaultStudentIDsArray: [String] {
        get { defaultStudentIDs as? [String] ?? [] }
        set { defaultStudentIDs = newValue as NSObject }
    }

    /// Typed accessor for tags Transformable
    var tagsArray: [String] {
        get { tags as? [String] ?? [] }
        set { tags = newValue as NSObject }
    }
}
