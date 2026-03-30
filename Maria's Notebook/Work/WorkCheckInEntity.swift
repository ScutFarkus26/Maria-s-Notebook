import Foundation
import CoreData
import SwiftUI

// MARK: - Enums

enum WorkCheckInStatus: String, Codable, CaseIterable, Sendable {
    case scheduled = "Scheduled"
    case completed = "Completed"
    case skipped = "Skipped"

    // MARK: - Styling

    /// Standard color for this check-in status
    var color: Color {
        switch self {
        case .completed: return .green
        case .skipped: return .red
        case .scheduled: return .orange
        }
    }

    /// System icon name for this status
    var iconName: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .scheduled: return "clock"
        }
    }

    /// Display label for menus and UI
    var displayLabel: String {
        switch self {
        case .completed: return "Completed"
        case .skipped: return "Skipped"
        case .scheduled: return "Scheduled"
        }
    }

    /// Menu action label (e.g., "Mark Completed")
    var menuActionLabel: String {
        switch self {
        case .completed: return "Mark Completed"
        case .skipped: return "Mark Skipped"
        case .scheduled: return "Mark Scheduled"
        }
    }
}

// MARK: - Core Data Entity

@objc(WorkCheckIn)
public class WorkCheckIn: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var workID: String
    @NSManaged public var date: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var purpose: String

    // MARK: - Relationships
    @NSManaged public var work: WorkModel?
    @NSManaged public var notes: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "WorkCheckIn", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.workID = ""
        self.date = Date()
        self.statusRaw = WorkCheckInStatus.scheduled.rawValue
        self.purpose = ""
    }
}

// MARK: - Computed Properties

extension WorkCheckIn {
    var status: WorkCheckInStatus {
        get { WorkCheckInStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    // Computed property for backward compatibility with UUID
    var workIDUUID: UUID? {
        get { UUID(uuidString: workID) }
        set { workID = newValue?.uuidString ?? "" }
    }

    // Convenience flags
    var isScheduled: Bool { status == .scheduled }
    var isCompleted: Bool { status == .completed }
    var isUpcoming: Bool { status == .scheduled && (date ?? .distantPast) > Date() }
}

// MARK: - Generated Accessors for To-Many Relationships

extension WorkCheckIn {
    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: Note)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: Note)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
