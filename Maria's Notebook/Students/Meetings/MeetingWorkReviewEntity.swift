import Foundation
import CoreData

@objc(CDMeetingWorkReview)
public class CDMeetingWorkReview: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var meetingID: String
    @NSManaged public var workID: String
    @NSManaged public var noteText: String
    @NSManaged public var createdAt: Date?

    // MARK: - Relationships
    @NSManaged public var meeting: CDStudentMeeting?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "MeetingWorkReview", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.meetingID = ""
        self.workID = ""
        self.noteText = ""
        self.createdAt = Date()
    }
}

// MARK: - Computed Properties

extension CDMeetingWorkReview {
    var meetingIDUUID: UUID? {
        get { UUID(uuidString: meetingID) }
        set { meetingID = newValue?.uuidString ?? "" }
    }

    var workIDUUID: UUID? {
        get { UUID(uuidString: workID) }
        set { workID = newValue?.uuidString ?? "" }
    }
}
