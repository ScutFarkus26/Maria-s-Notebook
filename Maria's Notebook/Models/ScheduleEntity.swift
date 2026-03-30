import Foundation
import CoreData

@objc(Schedule)
public class CDSchedule: NSManagedObject {
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

extension CDSchedule {
    /// Days of the week for scheduling
}

// MARK: - Computed Properties

extension CDSchedule {
    /// Safely access slots
    var safeSlots: [CDScheduleSlot] {
        (slots as? Set<CDScheduleSlot>).map(Array.init) ?? []
    }

    /// Get slots for a specific weekday, sorted by time then sort order
    func slots(for weekday: Weekday) -> [CDScheduleSlot] {
        safeSlots.filter { $0.weekday == weekday }
            .sorted { lhs, rhs in
                let lhsTime = lhs.timeString ?? ""
                let rhsTime = rhs.timeString ?? ""
                if lhsTime.isEmpty && rhsTime.isEmpty { return lhs.sortOrder < rhs.sortOrder }
                if !lhsTime.isEmpty && rhsTime.isEmpty { return true }
                if lhsTime.isEmpty && !rhsTime.isEmpty { return false }

                if lhsTime != rhsTime {
                    if let lhsMinutes = timeToMinutes(lhsTime),
                       let rhsMinutes = timeToMinutes(rhsTime) {
                        return lhsMinutes < rhsMinutes
                    }
                    return lhsTime < rhsTime
                }

                return lhs.sortOrder < rhs.sortOrder
            }
    }

    /// Converts time string (e.g., "9:30" or "10:15") to minutes since midnight for proper sorting
    private func timeToMinutes(_ timeString: String) -> Int? {
        let components = timeString.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        return components[0] * 60 + components[1]
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

extension CDSchedule {
    @objc(addSlotsObject:)
    @NSManaged public func addToSlots(_ value: CDScheduleSlot)

    @objc(removeSlotsObject:)
    @NSManaged public func removeFromSlots(_ value: CDScheduleSlot)

    @objc(addSlots:)
    @NSManaged public func addToSlots(_ values: NSSet)

    @objc(removeSlots:)
    @NSManaged public func removeFromSlots(_ values: NSSet)
}
