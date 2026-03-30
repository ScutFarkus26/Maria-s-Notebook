import Foundation
import CoreData

@objc(Schedule)
public class Schedule: NSManagedObject {
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

extension Schedule {
    /// Days of the week for scheduling
    enum Weekday: String, Codable, CaseIterable, Identifiable, Sendable {
        case sunday = "Sunday"
        case monday = "Monday"
        case tuesday = "Tuesday"
        case wednesday = "Wednesday"
        case thursday = "Thursday"
        case friday = "Friday"
        case saturday = "Saturday"

        public var id: String { rawValue }

        public var shortName: String {
            switch self {
            case .sunday: return "Sun"
            case .monday: return "Mon"
            case .tuesday: return "Tue"
            case .wednesday: return "Wed"
            case .thursday: return "Thu"
            case .friday: return "Fri"
            case .saturday: return "Sat"
            }
        }

        public var calendarWeekday: Int {
            switch self {
            case .sunday: return 1
            case .monday: return 2
            case .tuesday: return 3
            case .wednesday: return 4
            case .thursday: return 5
            case .friday: return 6
            case .saturday: return 7
            }
        }

        public static func from(calendarWeekday: Int) -> Weekday? {
            switch calendarWeekday {
            case 1: return .sunday
            case 2: return .monday
            case 3: return .tuesday
            case 4: return .wednesday
            case 5: return .thursday
            case 6: return .friday
            case 7: return .saturday
            default: return nil
            }
        }

        /// School days (Mon-Fri)
        public static var schoolDays: [Weekday] {
            [.monday, .tuesday, .wednesday, .thursday, .friday]
        }
    }
}

// MARK: - Computed Properties

extension Schedule {
    /// Safely access slots
    var safeSlots: [ScheduleSlot] {
        (slots as? Set<ScheduleSlot>).map(Array.init) ?? []
    }

    /// Get slots for a specific weekday, sorted by time then sort order
    func slots(for weekday: Weekday) -> [ScheduleSlot] {
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

extension Schedule {
    @objc(addSlotsObject:)
    @NSManaged public func addToSlots(_ value: ScheduleSlot)

    @objc(removeSlotsObject:)
    @NSManaged public func removeFromSlots(_ value: ScheduleSlot)

    @objc(addSlots:)
    @NSManaged public func addToSlots(_ values: NSSet)

    @objc(removeSlots:)
    @NSManaged public func removeFromSlots(_ values: NSSet)
}
