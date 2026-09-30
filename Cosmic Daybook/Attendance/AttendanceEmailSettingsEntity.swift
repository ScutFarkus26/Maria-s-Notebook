import Foundation
import CoreData

/// The guide's front-desk attendance email settings, carried to the assistants:
/// the recipients, the report format, and the time the front desk needs it by.
///
/// The guide sets them in Settings › Communication › Attendance Email, where
/// they are iCloud key-value settings (`AttendanceEmailPrefs`) that only the
/// guide's own devices read. The notebook copies them into this one row in the
/// classroom share (schema 12) so the Daybook Assistant writes the same email
/// to the same people. Only the lead guide writes it; the newest row wins.
/// Read and write it through `AttendanceEmailLog`, never directly.
@objc(CDAttendanceEmailSettings)
nonisolated public class CDAttendanceEmailSettings: NSManagedObject {
    @NSManaged public var id: UUID?
    /// Whether the guide has the attendance email turned on.
    @NSManaged public var isEnabled: Bool
    /// The recipients as the guide typed them: commas or semicolons between.
    @NSManaged public var toAddresses: String?
    /// `AttendanceEmailNameOrder` raw value.
    @NSManaged public var nameOrderRaw: String?
    @NSManaged public var groupByLevel: Bool
    /// When the front desk needs it by, in minutes after midnight (9:00 = 540).
    @NSManaged public var deadlineMinutes: Int32
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AttendanceEmailSettings", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.isEnabled = true
        self.deadlineMinutes = Int32(AttendanceEmailLog.defaultDeadlineMinutes)
        self.modifiedAt = Date()
    }
}

nonisolated extension CDAttendanceEmailSettings: Identifiable {}
