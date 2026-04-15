import Foundation
import CoreData

@objc(CDScheduledMeeting)
public class CDScheduledMeeting: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var date: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var _participantIDsData: Data?
    @NSManaged public var workID: String?
    @NSManaged public var isGroupMeeting: Bool

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ScheduledMeeting", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.date = Calendar.current.startOfDay(for: Date())
        self.createdAt = Date()
        self.isGroupMeeting = false
    }
}

// MARK: - Computed Properties

extension CDScheduledMeeting {
    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }

    var participantStudentIDs: [String] {
        get { CloudKitStringArrayStorage.decode(from: _participantIDsData) }
        set { _participantIDsData = CloudKitStringArrayStorage.encode(newValue) }
    }

    /// All student IDs involved in this meeting.
    /// For single-student meetings returns `[studentID]`.
    /// For group meetings returns the full participant list.
    var allStudentIDs: [String] {
        if isGroupMeeting, !participantStudentIDs.isEmpty {
            return participantStudentIDs
        }
        return studentID.isEmpty ? [] : [studentID]
    }

    var workIDUUID: UUID? {
        get { UUID(uuidString: workID ?? "") }
        set { workID = newValue?.uuidString ?? "" }
    }
}
