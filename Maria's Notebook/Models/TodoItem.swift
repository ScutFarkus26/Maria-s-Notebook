import Foundation
import SwiftData
import SwiftUI

enum TodoMood: String, Codable, CaseIterable, Sendable {
    case energized = "Energized"
    case focused = "Focused"
    case stressed = "Stressed"
    case overwhelmed = "Overwhelmed"
    case satisfied = "Satisfied"
    case frustrated = "Frustrated"
    case motivated = "Motivated"
    case tired = "Tired"
    
    var emoji: String {
        switch self {
        case .energized: return "⚡️"
        case .focused: return "🎯"
        case .stressed: return "😰"
        case .overwhelmed: return "🤯"
        case .satisfied: return "😊"
        case .frustrated: return "😤"
        case .motivated: return "🔥"
        case .tired: return "😴"
        }
    }
    
    var color: Color {
        switch self {
        case .energized: return .yellow
        case .focused: return .blue
        case .stressed: return .orange
        case .overwhelmed: return .red
        case .satisfied: return .green
        case .frustrated: return .purple
        case .motivated: return .pink
        case .tired: return .gray
        }
    }
}

enum RecurrencePattern: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .none: return "calendar"
        case .daily: return "arrow.clockwise"
        case .weekdays: return "calendar.badge.clock"
        case .weekly: return "calendar.badge.clock"
        case .biweekly: return "calendar.badge.clock"
        case .monthly: return "calendar.badge.clock"
        case .yearly: return "calendar.badge.clock"
        case .custom: return "calendar.badge.clock"
        }
    }
    
    var description: String {
        switch self {
        case .none: return "Does not repeat"
        case .daily: return "Every day"
        case .weekdays: return "Every weekday (Mon-Fri)"
        case .weekly: return "Every week"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        case .custom: return "Custom interval"
        }
    }

    var shortLabel: String {
        switch self {
        case .none: return ""
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .biweekly: return "2 Weeks"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .custom: return "Custom"
        }
    }
    
    /// Calculate the next due date based on the current due date
    /// For `.custom`, returns nil — handled externally using `customIntervalDays`.
    func nextDate(after date: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .none, .custom:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            // Find next weekday
            guard var nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            while calendar.isDateInWeekend(nextDate) {
                guard let next = calendar.date(byAdding: .day, value: 1, to: nextDate) else { return nil }
                nextDate = next
            }
            return nextDate
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

enum TodoPriority: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    var icon: String {
        switch self {
        case .none: return "circle"
        case .low: return "arrow.down.circle"
        case .medium: return "equal.circle"
        case .high: return "arrow.up.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        case .none: return 3
        }
    }
}

@Model
final class TodoItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date?
    var orderIndex: Int = 0
    var dueDate: Date?
    var scheduledDate: Date? // When to work on it (appears in Today view)
    var isSomeday: Bool = false // Deferred — hidden from Inbox/Today/Upcoming
    var repeatAfterCompletion: Bool = false // Recur relative to completion date, not calendar
    var customIntervalDays: Int? // Custom recurrence interval in days (e.g., 14 = every 2 weeks)
    private var priorityRaw: String = TodoPriority.none.rawValue
    private var recurrenceRaw: String = RecurrencePattern.none.rawValue
    
    // Store student IDs as strings for CloudKit compatibility
    var studentIDs: [String] = []
    
    // Store linked work item ID as string for CloudKit compatibility
    var linkedWorkItemID: String?
    
    // Store attachment file paths (CloudKit compatible)
    var attachmentPaths: [String] = []
    
    // Time tracking (in minutes)
    var estimatedMinutes: Int?
    var actualMinutes: Int?
    
    // Notifications/Reminders
    var reminderDate: Date?
    var notificationID: String? // Store the scheduled notification identifier
    
    // Mood and Reflection
    private var moodRaw: String? // Store mood as string
    var reflectionNotes: String = "" // Personal reflection/journal entry
    
    // Location-based Reminders
    var locationName: String? // e.g., "School", "Home", "Office"
    var locationLatitude: Double? // Latitude coordinate
    var locationLongitude: Double? // Longitude coordinate
    var locationRadius: Double = 100.0 // Geofence radius in meters (default 100m)
    var notifyOnEntry: Bool = true // Trigger on entering location
    var notifyOnExit: Bool = false // Trigger on leaving location
    
    // Tags/Labels
    var tags: [String] = [] // Colorful, filterable tags for organization
    
    // Relationship to subtasks (optional for CloudKit compatibility)
    @Relationship(deleteRule: .cascade, inverse: \TodoSubtask.todo)
    var subtasks: [TodoSubtask]? = []
    
    var priority: TodoPriority {
        get { TodoPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
    
    var recurrence: RecurrencePattern {
        get { RecurrencePattern(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }
    
    var mood: TodoMood? {
        get { moodRaw.flatMap { TodoMood(rawValue: $0) } }
        set { moodRaw = newValue?.rawValue }
    }
    
    /// Convenience computed property to get linked work item ID as UUID
    var linkedWorkItemUUID: UUID? {
        get { linkedWorkItemID.flatMap { UUID(uuidString: $0) } }
        set { linkedWorkItemID = newValue?.uuidString }
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        orderIndex: Int = 0,
        studentIDs: [String] = [],
        dueDate: Date? = nil,
        scheduledDate: Date? = nil,
        priority: TodoPriority = .none,
        recurrence: RecurrencePattern = .none,
        linkedWorkItemID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.orderIndex = orderIndex
        self.studentIDs = studentIDs
        self.dueDate = dueDate
        self.scheduledDate = scheduledDate
        self.priorityRaw = priority.rawValue
        self.recurrenceRaw = recurrence.rawValue
        self.linkedWorkItemID = linkedWorkItemID
    }
    
    /// Convenience computed property to get student IDs as UUIDs
    var studentUUIDs: [UUID] {
        get { studentIDs.compactMap { UUID(uuidString: $0) } }
        set { studentIDs = newValue.map { $0.uuidString } }
    }
    
    /// Check if todo is overdue
    var isOverdue: Bool {
        guard let dueDate = dueDate, !isCompleted else { return false }
        return dueDate < AppCalendar.startOfDay(Date())
    }
    
    /// Check if todo is due today
    var isDueToday: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
    
    /// Check if todo is due this week
    var isDueThisWeek: Bool {
        guard let dueDate = dueDate else { return false }
        let now = Date()
        guard let weekEnd = Calendar.current.date(
            byAdding: .day,
            value: 7,
            to: AppCalendar.startOfDay(now)
        ) else { return false }
        return dueDate >= AppCalendar.startOfDay(now) && dueDate < weekEnd
    }
    
    /// Get subtasks progress text
    var subtasksProgressText: String? {
        let items = subtasks ?? []
        guard !items.isEmpty else { return nil }
        let completed = items.filter { $0.isCompleted }.count
        return "\(completed)/\(items.count)"
    }

    /// Check if all subtasks are completed
    var allSubtasksCompleted: Bool {
        let items = subtasks ?? []
        guard !items.isEmpty else { return true }
        return items.allSatisfy { $0.isCompleted }
    }
    
    /// Check if todo has attachments
    var hasAttachments: Bool {
        !attachmentPaths.isEmpty
    }
    
    /// Check if todo has a reminder set
    var hasReminder: Bool {
        reminderDate != nil
    }
    
    /// Check if todo has mood or reflection notes
    var hasMoodOrReflection: Bool {
        mood != nil || !reflectionNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Check if todo has location-based reminder
    var hasLocationReminder: Bool {
        locationLatitude != nil && locationLongitude != nil
    }
    
    /// The effective date for sorting and grouping (scheduled date takes priority)
    var effectiveDate: Date? {
        scheduledDate ?? dueDate
    }
    
    /// Whether this todo has a hard deadline set
    var hasDeadline: Bool {
        dueDate != nil
    }
    
    /// Whether this todo is scheduled for today (checks scheduledDate first, falls back to dueDate)
    var isScheduledForToday: Bool {
        if let scheduled = scheduledDate {
            return Calendar.current.isDateInToday(scheduled)
        }
        if let due = dueDate {
            return Calendar.current.isDateInToday(due)
        }
        return false
    }
}
