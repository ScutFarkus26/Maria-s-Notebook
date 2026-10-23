import Foundation
import CoreData

/// One lane of the Schedules page: a room with its own timetable (our class,
/// the adolescent room) or a person (the guide, Morah Devora).
///
/// In the classroom share (schema 20), so the Daybook Assistant reads the same
/// lanes. Only the guide's devices write it, through `TimetableService`.
@objc(CDTimetableLane)
nonisolated public class CDTimetableLane: NSManagedObject {
    @NSManaged public var id: UUID?
    /// As the guide typed it.
    @NSManaged public var name: String
    /// A `TimetableLaneKind` raw value: "room" or "person".
    @NSManaged public var kindRaw: String
    /// True for the one person lane that reads the guide's planned lessons.
    @NSManaged public var isGuide: Bool
    @NSManaged public var sortOrder: Int64
    /// The lane's color, by name; empty for the page's own choice.
    @NSManaged public var colorRaw: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TimetableLane", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        let now = Date()
        self.createdAt = now
        self.modifiedAt = now
    }
}

nonisolated extension CDTimetableLane: Identifiable {}

nonisolated extension CDTimetableLane {
    var kind: TimetableLaneKind {
        get { TimetableLaneKind(rawValue: kindRaw) ?? .room }
        set { kindRaw = newValue.rawValue }
    }
}

nonisolated extension TimetableLaneSnapshot {
    /// The lane as stored; nil for a row without an id.
    init?(_ lane: CDTimetableLane) {
        guard let id = lane.id else { return nil }
        self.init(
            id: id,
            name: lane.name,
            kind: lane.kind,
            isGuide: lane.isGuide,
            sortOrder: Int(lane.sortOrder),
            colorRaw: lane.colorRaw
        )
    }
}
