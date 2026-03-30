import Foundation
import CoreData

@objc(ScheduleSlot)
public class ScheduleSlot: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var scheduleID: String
    @NSManaged public var studentID: String
    @NSManaged public var weekdayRaw: String
    @NSManaged public var timeString: String?
    @NSManaged public var sortOrder: Int64
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Relationships
    @NSManaged public var schedule: Schedule?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ScheduleSlot", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.scheduleID = ""
        self.studentID = ""
        self.weekdayRaw = Schedule.Weekday.monday.rawValue
        self.timeString = nil
        self.sortOrder = 0
        self.notes = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Computed Properties

extension ScheduleSlot {
    /// Computed property for weekday enum
    var weekday: Schedule.Weekday {
        get { Schedule.Weekday(rawValue: weekdayRaw) ?? .monday }
        set { weekdayRaw = newValue.rawValue }
    }

    /// Updates the modification timestamp
    func touch() {
        modifiedAt = Date()
    }
}
