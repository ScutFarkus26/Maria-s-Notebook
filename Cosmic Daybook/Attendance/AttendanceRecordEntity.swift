import Foundation
import CoreData
import SwiftUI

// MARK: - Attendance Status

// MARK: - Absence Reason

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

// MARK: - Cross-Store Notes

// Excluded from the assistant's companion app — see CDAttendanceStore.
#if !ASSISTANT_APP

nonisolated extension CDAttendanceRecord {
    /// Cross-store inverse: fetches Notes whose attendanceRecordID matches this
    /// record. Attendance is shared and Note is private, so the old to-many
    /// relationship could not survive the move.
    var unifiedNotes: [CDNote] {
        guard let id, let ctx = managedObjectContext else { return [] }
        let req = CDFetchRequest(CDNote.self)
        req.predicate = NSPredicate(format: "attendanceRecordID == %@", id.uuidString)
        return (try? ctx.fetch(req)) ?? []
    }
}

#endif
