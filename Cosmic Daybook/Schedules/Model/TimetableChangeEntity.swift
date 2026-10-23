import Foundation
import CoreData

/// One day's change to the timetable: a block cancelled that day, a block
/// with other values that day ("changed", the replacement values in full), or
/// a person out that day ("out").
///
/// In the classroom share (schema 20). Only the guide's devices write it,
/// through `TimetableService`. Two of his devices can each write one for the
/// same block and day before the other's arrives; readers take the newest.
@objc(CDTimetableChange)
nonisolated public class CDTimetableChange: NSManagedObject {
    @NSManaged public var id: UUID?
    /// The day it applies to (start of day).
    @NSManaged public var day: Date?
    /// A `TimetableChangeKind` raw value.
    @NSManaged public var kindRaw: String
    /// The block cancelled or changed, as a string.
    @NSManaged public var blockID: String?
    /// The person lane that is out, as a string.
    @NSManaged public var laneID: String?
    // The replacement values, for "changed".
    @NSManaged public var startMinute: Int64
    @NSManaged public var lengthMinutes: Int64
    @NSManaged public var title: String
    @NSManaged public var note: String
    @NSManaged public var teacherLaneID: String?
    @NSManaged public var teacherName: String
    @NSManaged public var _studentIDsData: Data?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TimetableChange", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        let now = Date()
        self.createdAt = now
        self.modifiedAt = now
    }
}

nonisolated extension CDTimetableChange: Identifiable {}

nonisolated extension CDTimetableChange {
    /// Nil for a kind this build doesn't know.
    var kind: TimetableChangeKind? {
        get { TimetableChangeKind(rawValue: kindRaw) }
        set { kindRaw = newValue?.rawValue ?? "" }
    }

    var studentIDs: [String] {
        get { CloudKitStringArrayStorage.decode(from: _studentIDsData) }
        set { _studentIDsData = newValue.isEmpty ? nil : CloudKitStringArrayStorage.encode(newValue) }
    }

    /// The replacement values.
    var values: TimetableBlockValues {
        get {
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
        set {
            startMinute = Int64(newValue.startMinute)
            lengthMinutes = Int64(newValue.lengthMinutes)
            title = newValue.title
            note = newValue.note
            teacherLaneID = newValue.teacherLaneID?.uuidString
            teacherName = newValue.teacherName
            studentIDs = newValue.studentIDs
        }
    }
}

nonisolated extension TimetableChangeSnapshot {
    /// The change as stored; nil for a row without an id.
    init?(_ change: CDTimetableChange) {
        guard let id = change.id else { return nil }
        self.init(
            id: id,
            day: change.day,
            kind: change.kind,
            blockID: change.blockID.flatMap(UUID.init(uuidString:)),
            laneID: change.laneID.flatMap(UUID.init(uuidString:)),
            values: change.values,
            modifiedAt: change.modifiedAt
        )
    }
}
