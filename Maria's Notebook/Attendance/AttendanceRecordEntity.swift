import Foundation
import CoreData
import SwiftUI

// MARK: - Attendance Status

// MARK: - Absence Reason

// MARK: - Core Data Entity

@objc(CDAttendanceRecord)
public class CDAttendanceRecord: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var date: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var absenceReasonRaw: String

    // MARK: - Relationships
    @NSManaged public var notes: NSSet?

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

extension CDAttendanceRecord {
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

// MARK: - Generated Accessors for To-Many Relationships

extension CDAttendanceRecord {
    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: CDNote)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: CDNote)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
