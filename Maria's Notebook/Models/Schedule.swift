import Foundation
import SwiftData

/// Days of the week for scheduling
enum Weekday: String, Codable, CaseIterable, Identifiable, Sendable {
    case sunday = "Sunday"
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"

    var id: String { rawValue }

    var shortName: String {
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

    var calendarWeekday: Int {
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

    static func from(calendarWeekday: Int) -> Weekday? {
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
    static var schoolDays: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday]
    }
}

/// A recurring schedule (e.g., "Reading Support", "Kodesh Lessons")
@Model
final class Schedule: Identifiable {
    /// Unique identifier
    var id: UUID = UUID()

    /// Name of the schedule (e.g., "Reading Support", "Kodesh Lessons")
    var name: String = ""

    /// Optional description or notes about this schedule
    var notes: String = ""

    /// Color for display (stored as hex string for CloudKit compatibility)
    var colorHex: String = "#007AFF"

    /// Icon name (SF Symbol)
    var icon: String = "calendar"

    /// When this schedule was created
    var createdAt: Date = Date()

    /// When this schedule was last modified
    var modifiedAt: Date = Date()

    /// Slots in this schedule
    @Relationship(deleteRule: .cascade, inverse: \ScheduleSlot.schedule)
    var slots: [ScheduleSlot]? = []

    /// Safely access slots
    var safeSlots: [ScheduleSlot] {
        slots ?? []
    }

    /// Get slots for a specific weekday, sorted by time then sort order
    func slots(for weekday: Weekday) -> [ScheduleSlot] {
        safeSlots.filter { $0.weekday == weekday }
            .sorted { lhs, rhs in
                // Sort by time string first (empty times go last)
                let lhsTime = lhs.timeString ?? ""
                let rhsTime = rhs.timeString ?? ""
                if lhsTime.isEmpty && rhsTime.isEmpty { return lhs.sortOrder < rhs.sortOrder }
                if !lhsTime.isEmpty && rhsTime.isEmpty { return true }
                if lhsTime.isEmpty && !rhsTime.isEmpty { return false }
                
                // Compare by actual time value (minutes since midnight)
                if lhsTime != rhsTime {
                    if let lhsMinutes = timeToMinutes(lhsTime),
                       let rhsMinutes = timeToMinutes(rhsTime) {
                        return lhsMinutes < rhsMinutes
                    }
                    // Fallback to string comparison for invalid times
                    return lhsTime < rhsTime
                }
                
                // Then by sort order
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
        let days = Set(safeSlots.map { $0.weekday })
        return Weekday.allCases.filter { days.contains($0) }
    }

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        colorHex: String = "#007AFF",
        icon: String = "calendar",
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.colorHex = colorHex
        self.icon = icon
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Updates the modification timestamp
    func touch() {
        modifiedAt = Date()
    }
}

/// A slot within a schedule (links a student to a specific day/time)
@Model
final class ScheduleSlot: Identifiable {
    /// Unique identifier
    var id: UUID = UUID()

    /// The schedule this slot belongs to (stored as string for CloudKit)
    var scheduleID: String = ""

    /// The student assigned to this slot (stored as string for CloudKit)
    var studentID: String = ""

    /// Day of the week (stored as raw string for CloudKit)
    @RawCodable var weekday: Weekday = .monday

    /// Optional time (stored as string like "09:30" for CloudKit compatibility)
    var timeString: String?

    /// Sort order within the day
    var sortOrder: Int = 0

    /// Optional notes for this slot
    var notes: String = ""

    /// When this slot was created
    var createdAt: Date = Date()

    /// When this slot was last modified
    var modifiedAt: Date = Date()

    /// Parent schedule relationship
    var schedule: Schedule?

    init(
        id: UUID = UUID(),
        scheduleID: String = "",
        studentID: String,
        weekday: Weekday,
        timeString: String? = nil,
        sortOrder: Int = 0,
        notes: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.scheduleID = scheduleID
        self.studentID = studentID
        self.weekday = weekday
        self.timeString = timeString
        self.sortOrder = sortOrder
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Updates the modification timestamp
    func touch() {
        modifiedAt = Date()
    }
}
