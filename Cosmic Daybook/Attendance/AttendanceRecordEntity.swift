import Foundation
import CoreData
import SwiftUI

// MARK: - Core Data Entity

@objc(CDAttendanceRecord)
nonisolated public class CDAttendanceRecord: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var date: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var absenceReasonRaw: String
    /// `ClassroomRole` rawValue of whoever last marked this record (lead guide or assistant).
    @NSManaged public var recordedBy: String?
    /// Stable CloudKit user record name of the person who last marked this.
    /// The role alone can't separate one assistant from another.
    @NSManaged public var recordedByID: String?
    /// What that person calls themselves, captured on their own device —
    /// CloudKit withholds your own name from you, so it cannot be looked up.
    @NSManaged public var recordedByName: String?
    @NSManaged public var modifiedAt: Date?
    /// When the current status was set: "arrived 8:12". For Left Early it is
    /// the arrival, kept from the present or tardy mark before it. Unlike
    /// `modifiedAt`, a note edit leaves it alone. Nil while unmarked, on
    /// records marked before it existed, and on marks made on any day but the
    /// one they're for. Written by `CDAttendanceStore` with the status.
    @NSManaged public var markedAt: Date?
    /// When a child marked Left Early went home: "8:02 → 1:15". `markedAt`
    /// keeps the arrival. Nil for every other status, and for marks made on
    /// any day but the one they're for. Written by `CDAttendanceStore`.
    @NSManaged public var leftAt: Date?
    /// The day's attendance note ("dentist, back by 11"). It lives on the
    /// record, not in the private notes, so the guide and an assistant share
    /// it; write it through `CDAttendanceStore.updateNote`.
    @NSManaged public var note: String?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AttendanceRecord", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.date = Date()
        self.statusRaw = AttendanceStatus.unmarked.rawValue
        self.absenceReasonRaw = AbsenceReason.none.rawValue
    }
}

// MARK: - Computed Properties

nonisolated extension CDAttendanceRecord {
    // Computed enum mapping for convenient UI usage
    var status: AttendanceStatus {
        get { AttendanceStatus(rawValue: statusRaw) ?? .unmarked }
        set {
            statusRaw = newValue.rawValue
            // Clear absence reason if status is not absent
            if newValue != .absent {
                absenceReasonRaw = AbsenceReason.none.rawValue
            }
        }
    }

    // Computed property for absence reason
    var absenceReason: AbsenceReason {
        get { AbsenceReason(rawValue: absenceReasonRaw) ?? .none }
        set { absenceReasonRaw = newValue.rawValue }
    }

    // Computed property for backward compatibility with UUID
    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }
}
