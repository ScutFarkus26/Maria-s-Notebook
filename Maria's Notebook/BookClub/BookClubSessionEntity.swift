import Foundation
import CoreData

@objc(CDBookClubSession)
public class CDBookClubSession: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var packetID: String
    @NSManaged public var displayName: String
    @NSManaged public var startDate: Date?
    @NSManaged public var endDate: Date?
    @NSManaged public var cadenceRaw: String
    @NSManaged public var meetingWeekdayMask: Int64
    @NSManaged public var statusRaw: String
    @NSManaged public var studentIDsRaw: String
    @NSManaged public var rotateLeader: Bool
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var meetings: NSSet?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "BookClubSession", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.packetID = ""
        self.displayName = ""
        self.startDate = nil
        self.endDate = nil
        self.cadenceRaw = BookClubCadenceKind.weekly.rawValue
        self.meetingWeekdayMask = 0
        self.statusRaw = BookClubSessionStatus.planned.rawValue
        self.studentIDsRaw = ""
        self.rotateLeader = true
        self.notes = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

extension CDBookClubSession {
    var cadenceKind: BookClubCadenceKind {
        get { BookClubCadenceKind(rawValue: cadenceRaw) ?? .weekly }
        set { cadenceRaw = newValue.rawValue }
    }

    var status: BookClubSessionStatus {
        get { BookClubSessionStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    var studentIDs: [UUID] {
        get {
            studentIDsRaw
                .split(separator: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            studentIDsRaw = newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    var meetingsSet: Set<CDBookClubMeeting> {
        (meetings as? Set<CDBookClubMeeting>) ?? []
    }

    var orderedMeetings: [CDBookClubMeeting] {
        meetingsSet.sorted { $0.ordinal < $1.ordinal }
    }

    var packetUUID: UUID? {
        UUID(uuidString: packetID)
    }

    var displayTitle: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Book Club" : trimmed
    }
}

extension CDBookClubSession {
    static func defaultSortDescriptors() -> [NSSortDescriptor] {
        [
            NSSortDescriptor(keyPath: \CDBookClubSession.startDate, ascending: true),
            NSSortDescriptor(keyPath: \CDBookClubSession.createdAt, ascending: false)
        ]
    }

}
