import Foundation
import CoreData

@objc(CDYearPlanEntry)
nonisolated public class CDYearPlanEntry: NSManagedObject {
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

nonisolated extension CDYearPlanEntry {
    var status: YearPlanEntryStatus {
        get { YearPlanEntryStatus(rawValue: statusRaw) ?? .planned }
        set {
            statusRaw = newValue.rawValue
            modifiedAt = Date()
        }
    }

    var studentUUID: UUID? { UUID(uuidString: studentID) }
    var lessonUUID: UUID? { UUID(uuidString: lessonID) }

    var isPlanned: Bool { status == .planned }
    var isPromoted: Bool { status == .promoted }

    /// Whether the lesson behind this intention has already been given to this
    /// child. Derived from the presentation record rather than stored on the
    /// entry — see `YearPlanSatisfaction` for why, and for why re-dating an
    /// entry is not how you ask for a lesson to be given again.
    func isSatisfied(by satisfaction: YearPlanSatisfaction) -> Bool {
        satisfaction.isSatisfied(self)
    }

    /// Whether this intention was made for a school year that has since ended:
    /// still planned, dated, and dated before this year's first day. See
    /// `YearPlanStaleness` for why that is not the same as being behind.
    ///
    /// Pass `yearStart` at any call site that asks this more than once — the
    /// default recomputes (from a cache, but still) per call.
    func isCarriedOver(yearStart: Date = YearPlanStaleness.currentYearStart()) -> Bool {
        YearPlanStaleness.isCarriedOver(
            plannedDate: plannedDate, status: status, yearStart: yearStart
        )
    }

    /// Whether this entry's planned date is in the past, it hasn't been
    /// promoted, and the lesson has not in fact been given.
    ///
    /// The satisfaction clause is what stops a lesson given without being
    /// scheduled first — the ordinary case, a child ready this morning — from
    /// reading as behind pace for the rest of the year. The carried-over clause
    /// is the same idea one year out: a target from last April is last year's
    /// intention, not this year's debt, and the guide re-dates or skips it
    /// rather than chasing it. "Behind pace" keeps meaning what it always did:
    /// a target date *in this school year* that has passed with the lesson
    /// still ahead of her.
    func isBehindPace(
        satisfiedBy satisfaction: YearPlanSatisfaction,
        schoolYearStart: Date = YearPlanStaleness.currentYearStart()
    ) -> Bool {
        guard isPlanned, !isSatisfied(by: satisfaction) else { return false }
        guard !isCarriedOver(yearStart: schoolYearStart) else { return false }
        guard let date = plannedDate else { return false }
        return date < AppCalendar.startOfDay(Date())
    }
}
