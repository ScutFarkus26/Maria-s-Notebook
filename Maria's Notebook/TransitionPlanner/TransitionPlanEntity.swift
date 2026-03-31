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
    @NSManaged public var observationNotes: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "CDTransitionPlan", in: context)!
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

    @objc(addObservationNotesObject:)
    @NSManaged public func addToObservationNotes(_ value: CDNote)

    @objc(removeObservationNotesObject:)
    @NSManaged public func removeFromObservationNotes(_ value: CDNote)

    @objc(addObservationNotes:)
    @NSManaged public func addToObservationNotes(_ values: NSSet)

    @objc(removeObservationNotes:)
    @NSManaged public func removeFromObservationNotes(_ values: NSSet)
}
