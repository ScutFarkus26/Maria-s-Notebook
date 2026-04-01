import Foundation
import CoreData

@objc(CDTransitionPlan)
public class CDTransitionPlan: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var studentID: String
    @NSManaged public var fromLevelRaw: String
    @NSManaged public var toLevelRaw: String
    @NSManaged public var statusRaw: String
    @NSManaged public var targetDate: Date?
    @NSManaged public var notes: String

    // MARK: - Relationships
    @NSManaged public var checklistItems: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TransitionPlan", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.studentID = ""
        self.fromLevelRaw = "Lower Elementary"
        self.toLevelRaw = "Upper Elementary"
        self.statusRaw = TransitionStatus.notStarted.rawValue
        self.targetDate = nil
        self.notes = ""
    }
}

// MARK: - Enums

extension CDTransitionPlan {
}

// MARK: - Computed Properties

extension CDTransitionPlan {
    var studentUUID: UUID? {
        UUID(uuidString: studentID)
    }

    var status: TransitionStatus {
        get { TransitionStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    /// Cross-store inverse: fetches Notes whose transitionPlanID matches this plan.
    var observationNotes: [CDNote] {
        guard let id, let ctx = managedObjectContext else { return [] }
        let req = CDFetchRequest(CDNote.self)
        req.predicate = NSPredicate(format: "transitionPlanID == %@", id.uuidString)
        return (try? ctx.fetch(req)) ?? []
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDTransitionPlan {
    @objc(addChecklistItemsObject:)
    @NSManaged public func addToChecklistItems(_ value: CDTransitionChecklistItem)

    @objc(removeChecklistItemsObject:)
    @NSManaged public func removeFromChecklistItems(_ value: CDTransitionChecklistItem)

    @objc(addChecklistItems:)
    @NSManaged public func addToChecklistItems(_ values: NSSet)

    @objc(removeChecklistItems:)
    @NSManaged public func removeFromChecklistItems(_ values: NSSet)

}
