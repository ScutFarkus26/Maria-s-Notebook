import Foundation
import CoreData

@objc(CDBookClubMeeting)
public class CDBookClubMeeting: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var sessionID: String
    @NSManaged public var ordinal: Int32
    @NSManaged public var date: Date?
    @NSManaged public var readingLabel: String
    @NSManaged public var leaderStudentID: String
    @NSManaged public var isCompleted: Bool
    @NSManaged public var completedAt: Date?
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var session: CDBookClubSession?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "BookClubMeeting", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.sessionID = ""
        self.ordinal = 0
        self.date = nil
        self.readingLabel = ""
        self.leaderStudentID = ""
        self.isCompleted = false
        self.completedAt = nil
        self.notes = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

extension CDBookClubMeeting {
    var leaderStudentUUID: UUID? {
        UUID(uuidString: leaderStudentID)
    }

    func markCompleted(_ completed: Bool) {
        isCompleted = completed
        completedAt = completed ? Date() : nil
        modifiedAt = Date()
    }
}
