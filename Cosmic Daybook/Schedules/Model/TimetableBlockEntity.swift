import Foundation
import CoreData

/// One block in a lane: a weekly block on a weekday, between `validFrom` and
/// `validUntil`, or a one-off on `onDay` (an assembly, a trip, an early
/// dismissal).
///
/// In the classroom share (schema 20). Only the guide's devices write it,
/// through `TimetableService`. This Day and After never rewrites the weeks
/// already past: the block ends the day before, and a copy with the new values
/// starts that day.
@objc(CDTimetableBlock)
nonisolated public class CDTimetableBlock: NSManagedObject {
    @NSManaged public var id: UUID?
    /// The lane's `id`, as a string.
    @NSManaged public var laneID: String
    /// A `Weekday` raw value; nil for a one-off.
    @NSManaged public var weekdayRaw: String?
    /// A one-off's day (start of day); nil for a weekly block.
    @NSManaged public var onDay: Date?
    /// Minutes after midnight.
    @NSManaged public var startMinute: Int64
    @NSManaged public var lengthMinutes: Int64
    @NSManaged public var title: String
    @NSManaged public var note: String
    /// A person lane's `id` when it teaches this block (a turn in a room).
    @NSManaged public var teacherLaneID: String?
    /// Who teaches it when that isn't a person lane.
    @NSManaged public var teacherName: String
    /// The children, a JSON string array (`CloudKitStringArrayStorage`).
    @NSManaged public var _studentIDsData: Data?
    /// The first and last days a weekly block applies (start of day); nil is open-ended.
    @NSManaged public var validFrom: Date?
    @NSManaged public var validUntil: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TimetableBlock", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        let now = Date()
        self.createdAt = now
        self.modifiedAt = now
    }
}

nonisolated extension CDTimetableBlock: Identifiable {}

nonisolated extension CDTimetableBlock {
    var weekday: Weekday? {
        get { weekdayRaw.flatMap(Weekday.init(rawValue:)) }
        set { weekdayRaw = newValue?.rawValue }
    }

    var studentIDs: [String] {
        get { CloudKitStringArrayStorage.decode(from: _studentIDsData) }
        set { _studentIDsData = newValue.isEmpty ? nil : CloudKitStringArrayStorage.encode(newValue) }
    }

    var isOneOff: Bool { onDay != nil }

    /// What can be edited, as it stands.
    var values: TimetableBlockValues {
        TimetableBlockValues(
            startMinute: Int(startMinute),
            lengthMinutes: Int(lengthMinutes),
            title: title,
            note: note,
            teacherLaneID: teacherLaneID.flatMap(UUID.init(uuidString:)),
            teacherName: teacherName,
            studentIDs: studentIDs
        )
    }

    /// Writes `values`, assigning only what differs. True when anything did.
    @discardableResult
    func apply(_ values: TimetableBlockValues) -> Bool {
        guard self.values != values else { return false }
        if startMinute != Int64(values.startMinute) { startMinute = Int64(values.startMinute) }
        if lengthMinutes != Int64(values.lengthMinutes) { lengthMinutes = Int64(values.lengthMinutes) }
        if title != values.title { title = values.title }
        if note != values.note { note = values.note }
        let teacher = values.teacherLaneID?.uuidString
        if teacherLaneID != teacher { teacherLaneID = teacher }
        if teacherName != values.teacherName { teacherName = values.teacherName }
        if studentIDs != values.studentIDs { studentIDs = values.studentIDs }
        return true
    }
}

nonisolated extension TimetableBlockSnapshot {
    /// The block as stored; nil for a row without an id.
    init?(_ block: CDTimetableBlock) {
        guard let id = block.id else { return nil }
        self.init(
            id: id,
            laneID: UUID(uuidString: block.laneID),
            weekday: block.weekday,
            onDay: block.onDay,
            values: block.values,
            validFrom: block.validFrom,
            validUntil: block.validUntil
        )
    }
}
