import Foundation
import CoreData

@objc(StudentTrackEnrollmentEntity)
public class CDStudentTrackEnrollmentEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var studentID: String
    @NSManaged public var trackID: String
    @NSManaged public var startedAt: Date?
    @NSManaged public var isActive: Bool

    // MARK: - Relationships
    @NSManaged public var student: CDStudent?
    @NSManaged public var track: CDTrackEntity?

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

// MARK: - Cross-Store Inverse

extension CDStudentTrackEnrollmentEntity {
    /// Cross-store inverse: fetches Notes whose studentTrackEnrollmentID matches this enrollment.
    var richNotes: [CDNote] {
        guard let id, let ctx = managedObjectContext else { return [] }
        let req = CDFetchRequest(CDNote.self)
        req.predicate = NSPredicate(format: "studentTrackEnrollmentID == %@", id.uuidString)
        return (try? ctx.fetch(req)) ?? []
    }
}

