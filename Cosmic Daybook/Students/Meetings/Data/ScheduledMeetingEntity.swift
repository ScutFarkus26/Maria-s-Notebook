import Foundation
import CoreData

@objc(CDScheduledMeeting)
nonisolated public class CDScheduledMeeting: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var date: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var _participantIDsData: Data?
    @NSManaged public var workID: String?
    @NSManaged public var isGroupMeeting: Bool
    /// What the meeting is about, in the guide's words. Nil on bookings made
    /// before the field existed and on ones the guide made with a date alone.
    @NSManaged public var purpose: String?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ScheduledMeeting", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.date = AppCalendar.shared.startOfDay(for: Date())
        self.createdAt = Date()
        self.isGroupMeeting = false
    }
}

// MARK: - Computed Properties

nonisolated extension CDScheduledMeeting {
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
    /// For sequence meetings returns the full participant list.
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
