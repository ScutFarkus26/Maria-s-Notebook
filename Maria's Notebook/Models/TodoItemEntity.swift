import Foundation
import CoreData
import SwiftUI

@objc(TodoItemEntity)
public class TodoItemEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var notes: String
    @NSManaged public var isCompleted: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var completedAt: Date?
    @NSManaged public var orderIndex: Int64
    @NSManaged public var dueDate: Date?
    @NSManaged public var scheduledDate: Date?
    @NSManaged public var isSomeday: Bool
    @NSManaged public var repeatAfterCompletion: Bool
    @NSManaged public var customIntervalDays: Int64
    @NSManaged public var priorityRaw: String
    @NSManaged public var recurrenceRaw: String
    // Transformable [String] arrays stored as NSObject? in Core Data
    @NSManaged public var studentIDs: NSObject?
    @NSManaged public var linkedWorkItemID: String?
    @NSManaged public var attachmentPaths: NSObject?
    @NSManaged public var estimatedMinutes: Int64
    @NSManaged public var actualMinutes: Int64
    @NSManaged public var reminderDate: Date?
    @NSManaged public var notificationID: String?
    @NSManaged public var moodRaw: String?
    @NSManaged public var reflectionNotes: String
    @NSManaged public var locationName: String?
    @NSManaged public var locationLatitude: Double
    @NSManaged public var locationLongitude: Double
    @NSManaged public var locationRadius: Double
    @NSManaged public var notifyOnEntry: Bool
    @NSManaged public var notifyOnExit: Bool
    @NSManaged public var tags: NSObject?

    // MARK: - Relationships
    @NSManaged public var subtasks: NSSet?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TodoItem", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.notes = ""
        self.isCompleted = false
        self.createdAt = Date()
        self.completedAt = nil
        self.orderIndex = 0
        self.dueDate = nil
        self.scheduledDate = nil
        self.isSomeday = false
        self.repeatAfterCompletion = false
        self.customIntervalDays = 0
        self.priorityRaw = TodoPriority.none.rawValue
        self.recurrenceRaw = RecurrencePattern.none.rawValue
        self.studentIDs = nil
        self.linkedWorkItemID = nil
        self.attachmentPaths = nil
        self.estimatedMinutes = 0
        self.actualMinutes = 0
        self.reminderDate = nil
        self.notificationID = nil
        self.moodRaw = nil
        self.reflectionNotes = ""
        self.locationName = nil
        self.locationLatitude = 0
        self.locationLongitude = 0
        self.locationRadius = 100.0
        self.notifyOnEntry = true
        self.notifyOnExit = false
        self.tags = nil
    }
}

// MARK: - Computed Properties
extension TodoItemEntity {
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

    /// Typed accessor for studentIDs Transformable
    var studentIDsArray: [String] {
        get { studentIDs as? [String] ?? [] }
        set { studentIDs = newValue as NSObject }
    }

    /// Typed accessor for attachmentPaths Transformable
    var attachmentPathsArray: [String] {
        get { attachmentPaths as? [String] ?? [] }
        set { attachmentPaths = newValue as NSObject }
    }

    /// Typed accessor for tags Transformable
    var tagsArray: [String] {
        get { tags as? [String] ?? [] }
        set { tags = newValue as NSObject }
    }

    /// Convenience computed property to get student IDs as UUIDs
    var studentUUIDs: [UUID] {
        get { studentIDsArray.compactMap { UUID(uuidString: $0) } }
        set { studentIDsArray = newValue.map(\.uuidString) }
    }

    /// Convenience computed property to get linked work item ID as UUID
    var linkedWorkItemUUID: UUID? {
        get { linkedWorkItemID.flatMap { UUID(uuidString: $0) } }
        set { linkedWorkItemID = newValue?.uuidString }
    }

    /// Check if todo is overdue
    var isOverdue: Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    /// Check if todo is due today
    var isDueToday: Bool {
        guard let dueDate, !isCompleted else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    /// Check if todo is due this week
    var isDueThisWeek: Bool {
        guard let dueDate, !isCompleted else { return false }
        let now = Date()
        guard let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: now)) else { return false }
        return dueDate >= Calendar.current.startOfDay(for: now) && dueDate < weekEnd
    }

    /// Get subtasks progress text
    var subtasksProgressText: String? {
        let items = subtasks as? Set<TodoSubtaskEntity> ?? []
        guard !items.isEmpty else { return nil }
        let completed = items.filter(\.isCompleted).count
        return "\(completed)/\(items.count)"
    }

    /// Check if all subtasks are completed
    var allSubtasksCompleted: Bool {
        let items = subtasks as? Set<TodoSubtaskEntity> ?? []
        guard !items.isEmpty else { return true }
        return items.allSatisfy { $0.isCompleted }
    }

    /// Check if todo has attachments
    var hasAttachments: Bool {
        !attachmentPathsArray.isEmpty
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
        locationName != nil
    }

    /// The effective date for sorting and grouping (scheduled date takes priority)
    var effectiveDate: Date? {
        scheduledDate ?? dueDate
    }

    /// Whether this todo has a hard deadline set
    var hasDeadline: Bool {
        dueDate != nil
    }

    /// Whether this todo is scheduled for today
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

// MARK: - Generated Accessors for subtasks
extension TodoItemEntity {
    @objc(addSubtasksObject:)
    @NSManaged public func addToSubtasks(_ value: TodoSubtaskEntity)

    @objc(removeSubtasksObject:)
    @NSManaged public func removeFromSubtasks(_ value: TodoSubtaskEntity)

    @objc(addSubtasks:)
    @NSManaged public func addToSubtasks(_ values: NSSet)

    @objc(removeSubtasks:)
    @NSManaged public func removeFromSubtasks(_ values: NSSet)
}
