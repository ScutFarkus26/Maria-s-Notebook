import Foundation
import CoreData

@objc(Reminder)
public class Reminder: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var notes: String?
    @NSManaged public var dueDate: Date?
    @NSManaged public var isCompleted: Bool
    @NSManaged public var completedAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var eventKitReminderID: String?
    @NSManaged public var eventKitCalendarID: String?
    @NSManaged public var lastSyncedAt: Date?

    // MARK: - Relationships
    @NSManaged public var noteItems: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Reminder", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.notes = nil
        self.dueDate = nil
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.eventKitReminderID = nil
        self.eventKitCalendarID = nil
        self.lastSyncedAt = nil
    }
}

// MARK: - Computed Properties

extension Reminder {
    /// Mark this reminder as completed
    func markCompleted() {
        self.isCompleted = true
        self.completedAt = Calendar.current.startOfDay(for: Date())
        self.updatedAt = Date()
    }

    /// Mark this reminder as incomplete
    func markIncomplete() {
        self.isCompleted = false
        self.completedAt = nil
        self.updatedAt = Date()
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension Reminder {
    @objc(addNoteItemsObject:)
    @NSManaged public func addToNoteItems(_ value: Note)

    @objc(removeNoteItemsObject:)
    @NSManaged public func removeFromNoteItems(_ value: Note)

    @objc(addNoteItems:)
    @NSManaged public func addToNoteItems(_ values: NSSet)

    @objc(removeNoteItems:)
    @NSManaged public func removeFromNoteItems(_ values: NSSet)
}
