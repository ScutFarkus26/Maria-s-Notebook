import Foundation
import CoreData
import SwiftUI

// MARK: - Attendance Status

enum AttendanceStatus: String, Codable, CaseIterable, Sendable {
    case unmarked
    case present
    case absent
    case tardy
    case leftEarly

    var displayName: String {
        switch self {
        case .unmarked: return "Unmarked"
        case .present: return "Present"
        case .absent: return "Absent"
        case .tardy: return "Tardy"
        case .leftEarly: return "Left Early"
        }
    }

    var color: Color {
        switch self {
        case .unmarked: return Color.gray.opacity(UIConstants.OpacityConstants.quarter)
        case .present: return Color.green.opacity(UIConstants.OpacityConstants.statusBg)
        case .absent: return Color.red.opacity(UIConstants.OpacityConstants.statusBg)
        case .tardy: return Color.blue.opacity(UIConstants.OpacityConstants.statusBg)
        case .leftEarly: return Color.purple.opacity(UIConstants.OpacityConstants.statusBg)
        }
    }

    /// Returns the next status in the cycle
    func next() -> AttendanceStatus {
        switch self {
        case .unmarked: return .present
        case .present: return .absent
        case .absent: return .tardy
        case .tardy: return .leftEarly
        case .leftEarly: return .unmarked
        }
    }
}

// MARK: - Absence Reason

enum AbsenceReason: String, Codable, CaseIterable, Sendable {
    case none
    case sick
    case vacation

    var displayName: String {
        switch self {
        case .none: return ""
        case .sick: return "Sick"
        case .vacation: return "Vacation"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle"
        case .sick: return "cross.case.fill"
        case .vacation: return "beach.umbrella.fill"
        }
    }
}

// MARK: - Core Data Entity

@objc(AttendanceRecord)
public class AttendanceRecord: NSManagedObject {
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

extension AttendanceRecord {
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

extension AttendanceRecord {
    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: Note)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: Note)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
