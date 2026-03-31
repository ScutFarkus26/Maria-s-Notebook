import Foundation
import CoreData

@objc(CDStudentMeeting)
public class CDStudentMeeting: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var date: Date?
    @NSManaged public var completed: Bool
    @NSManaged public var reflection: String
    @NSManaged public var focus: String
    @NSManaged public var requests: String
    @NSManaged public var guideNotes: String

    // MARK: - Relationships
    @NSManaged public var notes: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "StudentMeeting", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.date = Date()
        self.completed = false
        self.reflection = ""
        self.focus = ""
        self.requests = ""
        self.guideNotes = ""
    }
}

// MARK: - Computed Properties

extension CDStudentMeeting {
    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDStudentMeeting {
    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: CDNote)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: CDNote)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
