import Foundation
import CoreData

@objc(WorkParticipantEntity)
public class WorkParticipantEntity: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var completedAt: Date?

    // MARK: - Relationships
    @NSManaged public var work: WorkModel?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "WorkParticipantEntity", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.completedAt = nil
    }
}

// MARK: - Computed Properties

extension WorkParticipantEntity {
    // Computed property for backward compatibility with UUID
    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }
}
