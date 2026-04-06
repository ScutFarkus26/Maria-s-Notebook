import Foundation
import CoreData

@objc(CDYearPlanEntry)
public class CDYearPlanEntry: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var lessonID: String
    @NSManaged public var plannedDate: Date?
    @NSManaged public var spacingSchoolDays: Int64
    @NSManaged public var sequenceGroupKey: String
    @NSManaged public var orderInSequence: Int64
    @NSManaged public var statusRaw: String
    @NSManaged public var promotedAssignmentID: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "YearPlanEntry", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.lessonID = ""
        self.plannedDate = nil
        self.spacingSchoolDays = 3
        self.sequenceGroupKey = ""
        self.orderInSequence = 0
        self.statusRaw = YearPlanEntryStatus.planned.rawValue
        self.promotedAssignmentID = nil
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Status Enum

enum YearPlanEntryStatus: String {
    case planned
    case promoted
    case skipped
}

// MARK: - Computed Properties

extension CDYearPlanEntry {
    var status: YearPlanEntryStatus {
        get { YearPlanEntryStatus(rawValue: statusRaw) ?? .planned }
        set {
            statusRaw = newValue.rawValue
            modifiedAt = Date()
        }
    }

    var studentUUID: UUID? { UUID(uuidString: studentID) }
    var lessonUUID: UUID? { UUID(uuidString: lessonID) }
    var promotedAssignmentUUID: UUID? {
        guard let idStr = promotedAssignmentID else { return nil }
        return UUID(uuidString: idStr)
    }

    var isPlanned: Bool { status == .planned }
    var isPromoted: Bool { status == .promoted }
    var isSkipped: Bool { status == .skipped }

    /// Whether this entry's planned date is in the past and it hasn't been promoted.
    var isBehindPace: Bool {
        guard isPlanned, let date = plannedDate else { return false }
        return date < AppCalendar.startOfDay(Date())
    }
}
