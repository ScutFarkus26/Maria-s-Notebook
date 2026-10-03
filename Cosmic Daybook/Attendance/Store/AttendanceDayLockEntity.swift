import Foundation
import CoreData

/// A day whose attendance the lead guide has locked. A day is locked while a
/// row exists for it; unlocking deletes the row.
///
/// Lives in the classroom share (schema 9) so an assistant's device sees the
/// same locks the guide set. It replaces the `Attendance.locked.<yyyy-MM-dd>`
/// iCloud key-value setting, which only the guide's own devices could read.
/// Read and write it through `AttendanceDayLocks`, never directly.
@objc(CDAttendanceDayLock)
nonisolated public class CDAttendanceDayLock: NSManagedObject {
    @NSManaged public var id: UUID?
    /// Start of the locked day in the local calendar, like `AttendanceRecord.date`.
    @NSManaged public var date: Date?
    @NSManaged public var lockedAt: Date?
    /// CloudKit user record name of the guide who locked it, when known.
    @NSManaged public var lockedByID: String?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AttendanceDayLock", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.lockedAt = Date()
    }
}

nonisolated extension CDAttendanceDayLock: Identifiable {}
