import Foundation
import CoreData

@objc(StudentTrackEnrollmentEntity)
public class StudentTrackEnrollmentEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var studentID: String
    @NSManaged public var trackID: String
    @NSManaged public var startedAt: Date?
    @NSManaged public var isActive: Bool

    // MARK: - Relationships
    @NSManaged public var richNotes: NSSet?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "StudentTrackEnrollment", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.studentID = ""
        self.trackID = ""
        self.startedAt = nil
        self.isActive = true
    }
}

// MARK: - Generated Accessors for richNotes
extension StudentTrackEnrollmentEntity {
    @objc(addRichNotesObject:)
    @NSManaged public func addToRichNotes(_ value: NSManagedObject)

    @objc(removeRichNotesObject:)
    @NSManaged public func removeFromRichNotes(_ value: NSManagedObject)

    @objc(addRichNotes:)
    @NSManaged public func addToRichNotes(_ values: NSSet)

    @objc(removeRichNotes:)
    @NSManaged public func removeFromRichNotes(_ values: NSSet)
}
