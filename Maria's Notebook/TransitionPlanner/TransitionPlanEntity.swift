import Foundation
import CoreData

@objc(TransitionPlan)
public class TransitionPlan: NSManagedObject {
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

extension TransitionPlan {
    enum TransitionStatus: String, CaseIterable, Identifiable, Sendable {
        case notStarted
        case inProgress
        case ready
        case transitioned

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .notStarted: return "Not Started"
            case .inProgress: return "In Progress"
            case .ready: return "Ready"
            case .transitioned: return "Transitioned"
            }
        }

        public var icon: String {
            switch self {
            case .notStarted: return "circle"
            case .inProgress: return "arrow.forward.circle"
            case .ready: return "checkmark.circle"
            case .transitioned: return "checkmark.circle.fill"
            }
        }
    }
}

// MARK: - Computed Properties

extension TransitionPlan {
    var studentUUID: UUID? {
        UUID(uuidString: studentID)
    }

    var status: TransitionStatus {
        get { TransitionStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension TransitionPlan {
    @objc(addChecklistItemsObject:)
    @NSManaged public func addToChecklistItems(_ value: TransitionChecklistItem)

    @objc(removeChecklistItemsObject:)
    @NSManaged public func removeFromChecklistItems(_ value: TransitionChecklistItem)

    @objc(addChecklistItems:)
    @NSManaged public func addToChecklistItems(_ values: NSSet)

    @objc(removeChecklistItems:)
    @NSManaged public func removeFromChecklistItems(_ values: NSSet)

    @objc(addObservationNotesObject:)
    @NSManaged public func addToObservationNotes(_ value: Note)

    @objc(removeObservationNotesObject:)
    @NSManaged public func removeFromObservationNotes(_ value: Note)

    @objc(addObservationNotes:)
    @NSManaged public func addToObservationNotes(_ values: NSSet)

    @objc(removeObservationNotes:)
    @NSManaged public func removeFromObservationNotes(_ values: NSSet)
}
