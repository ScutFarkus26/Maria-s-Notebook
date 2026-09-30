import Foundation
import CoreData

/// One front-desk attendance email that went out: which day it reported, when,
/// and who sent it.
///
/// Lives in the classroom share (schema 12), so the guide and every assistant
/// see that the day's email went and nobody sends it twice. A day can hold
/// several (an update sent after a late arrival); the newest is the one shown.
/// Read and write it through `AttendanceEmailLog`, never directly.
@objc(CDAttendanceEmailSend)
nonisolated public class CDAttendanceEmailSend: NSManagedObject {
    @NSManaged public var id: UUID?
    /// Start of the reported day in the local calendar, like `AttendanceRecord.date`.
    @NSManaged public var date: Date?
    @NSManaged public var sentAt: Date?
    /// The sender's `ClassroomRole` raw value.
    @NSManaged public var sentBy: String?
    /// CloudKit user record name of the sender, when known.
    @NSManaged public var sentByID: String?
    /// The name an assistant typed on her phone; the guide's sends carry none.
    @NSManaged public var sentByName: String?
    /// Set when Mail couldn't say it sent and the sender said it did (or the
    /// front desk was told another way).
    @NSManaged public var wasConfirmedByHand: Bool

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AttendanceEmailSend", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.sentAt = Date()
    }
}

nonisolated extension CDAttendanceEmailSend: Identifiable {}
