import Foundation
import CoreData
import SwiftUI

// MARK: - Enums

// MARK: - Core Data Entity

@objc(WorkCheckIn)
public class CDWorkCheckIn: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var workID: String
    @NSManaged public var date: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var purpose: String

    // MARK: - Relationships
    @NSManaged public var work: CDWorkModel?
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

extension CDWorkCheckIn {
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

extension CDWorkCheckIn {
    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: CDNote)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: CDNote)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
