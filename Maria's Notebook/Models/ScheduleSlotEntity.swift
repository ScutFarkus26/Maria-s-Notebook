import Foundation
import CoreData

@objc(ScheduleSlot)
public class CDScheduleSlot: NSManagedObject {
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
    @NSManaged public var schedule: CDSchedule?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ScheduleSlot", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.scheduleID = ""
        self.studentID = ""
        self.weekdayRaw = Weekday.monday.rawValue
        self.timeString = nil
        self.sortOrder = 0
        self.notes = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Computed Properties

extension CDScheduleSlot {
    /// Computed property for weekday enum
    var weekday: Weekday {
        get { Weekday(rawValue: weekdayRaw) ?? .monday }
        set { weekdayRaw = newValue.rawValue }
    }

    /// Updates the modification timestamp
    func touch() {
        modifiedAt = Date()
    }
}
