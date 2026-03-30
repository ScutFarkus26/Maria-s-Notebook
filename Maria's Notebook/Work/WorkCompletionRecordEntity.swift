import Foundation
import CoreData

/// A historical record indicating that a student completed a piece of work
/// at a specific point in time. Multiple records for the same (workID, studentID)
/// pair preserve the full completion history.
@objc(WorkCompletionRecord)
public class CDWorkCompletionRecord: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var workID: String
    @NSManaged public var studentID: String
    @NSManaged public var completedAt: Date?

    // MARK: - Relationships
    @NSManaged public var notes: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "WorkCompletionRecord", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.workID = ""
        self.studentID = ""
        self.completedAt = Date()
    }
}

// MARK: - Computed Properties

extension CDWorkCompletionRecord {
    var workIDUUID: UUID? {
        get { UUID(uuidString: workID) }
        set { workID = newValue?.uuidString ?? "" }
    }

    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDWorkCompletionRecord {
    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: CDNote)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: CDNote)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
