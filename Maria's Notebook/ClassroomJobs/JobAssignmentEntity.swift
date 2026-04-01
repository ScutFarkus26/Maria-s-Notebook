import Foundation
import CoreData

@objc(CDJobAssignment)
public class CDJobAssignment: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var jobID: String
    @NSManaged public var studentID: String
    @NSManaged public var weekStartDate: Date?
    @NSManaged public var isCompleted: Bool

    // MARK: - Relationships
    @NSManaged public var job: CDClassroomJob?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "JobAssignment", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.jobID = ""
        self.studentID = ""
        self.weekStartDate = Date()
        self.isCompleted = false
    }
}

// MARK: - Computed Properties

extension CDJobAssignment {
    var studentUUID: UUID? {
        UUID(uuidString: studentID)
    }
}
