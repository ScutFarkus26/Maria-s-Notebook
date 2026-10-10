import Foundation
import CoreData

@objc(Schedule)
nonisolated public class CDSchedule: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var notes: String
    @NSManaged public var colorHex: String
    @NSManaged public var icon: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Relationships
    @NSManaged public var slots: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Schedule", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.name = ""
        self.notes = ""
        self.colorHex = "#007AFF"
        self.icon = "calendar"
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Enums

nonisolated extension CDSchedule {
    /// Days of the week for scheduling
}

// MARK: - Computed Properties

nonisolated extension CDSchedule {
    /// Safely access slots
    var safeSlots: [CDScheduleSlot] {
        (slots as? Set<CDScheduleSlot>).map(Array.init) ?? []
    }

    /// Get slots for a specific weekday, sorted by time (`ScheduleTime`) then sort order
    func slots(for weekday: Weekday) -> [CDScheduleSlot] {
        safeSlots.filter { $0.weekday == weekday }
            .sorted { lhs, rhs in
                switch ScheduleTime.order(lhs.timeString, rhs.timeString) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return lhs.sortOrder < rhs.sortOrder
                }
            }
    }

    /// Get all weekdays that have slots
    var activeWeekdays: [Weekday] {
        let days = Set(safeSlots.map(\.weekday))
        return Weekday.allCases.filter { days.contains($0) }
    }

    /// Updates the modification timestamp
    func touch() {
        modifiedAt = Date()
    }
}

// MARK: - Generated Accessors for To-Many Relationships

nonisolated extension CDSchedule {
    @objc(addSlotsObject:)
    @NSManaged public func addToSlots(_ value: CDScheduleSlot)

    @objc(removeSlotsObject:)
    @NSManaged public func removeFromSlots(_ value: CDScheduleSlot)

    @objc(addSlots:)
    @NSManaged public func addToSlots(_ values: NSSet)

    @objc(removeSlots:)
    @NSManaged public func removeFromSlots(_ values: NSSet)
}
