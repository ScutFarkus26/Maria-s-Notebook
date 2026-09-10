import Foundation
import CoreData
import SwiftUI

// MARK: - Enums

// MARK: - Core Data Entity

@objc(CDWorkCheckIn)
nonisolated public class CDWorkCheckIn: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var workID: String
    @NSManaged public var date: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var purpose: String
    @NSManaged public var studentInitiated: Bool

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
        self.studentInitiated = false
    }
}

// MARK: - Creation

nonisolated extension CDWorkCheckIn {
    /// The one way to make a check-in. Writes the `workID` string and the
    /// `work` relationship together, so the check-in is found by either and
    /// goes with its work when the work is deleted.
    ///
    /// Five screens used to write only the string — the week plan drop, the
    /// work detail calendar, Quick New Work, the Works agenda and the MCP
    /// assign_work path — and a check-in made that way read as "Untitled work
    /// — unassigned" wherever the relationship was the lookup.
    @discardableResult
    static func make(
        for work: CDWorkModel,
        on date: Date,
        purpose: String = "",
        status: WorkCheckInStatus = .scheduled,
        studentInitiated: Bool = false,
        in context: NSManagedObjectContext
    ) -> CDWorkCheckIn {
        let checkIn = CDWorkCheckIn(context: context)
        checkIn.workID = work.id?.uuidString ?? ""
        checkIn.date = date
        checkIn.status = status
        checkIn.purpose = purpose.trimmed()
        checkIn.studentInitiated = studentInitiated
        checkIn.work = work
        return checkIn
    }

    /// The work this check-in belongs to: the relationship when it was set,
    /// otherwise the row the `workID` string names. Readers use this rather
    /// than `work` so a check-in written before the relationship was always
    /// set still resolves.
    func resolvedWork(in context: NSManagedObjectContext? = nil) -> CDWorkModel? {
        if let work, !work.isDeleted { return work }
        guard let context = context ?? managedObjectContext, let id = UUID(uuidString: workID) else { return nil }
        return context.object(CDWorkModel.self, id: id)
    }
}

// MARK: - Computed Properties

nonisolated extension CDWorkCheckIn {
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
}

// MARK: - Generated Accessors for To-Many Relationships

nonisolated extension CDWorkCheckIn {
    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: CDNote)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: CDNote)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
