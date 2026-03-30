import Foundation
import CoreData

/// A junction model linking Notes to Students for efficient querying.
/// Created automatically when a note's scope includes multiple students.
@objc(NoteStudentLink)
public class NoteStudentLink: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var noteID: String
    @NSManaged public var studentID: String

    // MARK: - Relationships
    @NSManaged public var note: Note?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "NoteStudentLink", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.noteID = ""
        self.studentID = ""
    }
}

// MARK: - Computed Properties

extension NoteStudentLink {
    var noteIDUUID: UUID? {
        get { UUID(uuidString: noteID) }
        set { noteID = newValue?.uuidString ?? "" }
    }

    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }
}
