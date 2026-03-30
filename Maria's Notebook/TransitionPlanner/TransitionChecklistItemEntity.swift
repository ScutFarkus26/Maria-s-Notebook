import Foundation
import CoreData

@objc(TransitionChecklistItem)
public class CDTransitionChecklistItem: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var transitionPlanID: String
    @NSManaged public var title: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var isCompleted: Bool
    @NSManaged public var completedAt: Date?
    @NSManaged public var sortOrder: Int64
    @NSManaged public var notes: String

    // MARK: - Relationships
    @NSManaged public var transitionPlan: CDTransitionPlan?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TransitionChecklistItem", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.transitionPlanID = ""
        self.title = ""
        self.categoryRaw = ChecklistCategory.academic.rawValue
        self.isCompleted = false
        self.completedAt = nil
        self.sortOrder = 0
        self.notes = ""
    }
}

// MARK: - Enums

extension CDTransitionChecklistItem {
}

// MARK: - Computed Properties

extension CDTransitionChecklistItem {
    var category: ChecklistCategory {
        get { ChecklistCategory(rawValue: categoryRaw) ?? .academic }
        set { categoryRaw = newValue.rawValue }
    }
}
