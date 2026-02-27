import Foundation
import SwiftData

/// A reminder model that syncs with Apple's Reminders app via EventKit.
/// Reminders are displayed in the Today view and can be synced from a specific Reminders list.
@Model
final class Reminder: Identifiable {
    #Index<Reminder>([\.isCompleted], [\.eventKitReminderID])

    /// Unique identifier for this reminder
    var id: UUID = UUID()
    
    /// The title/text of the reminder
    var title: String = ""
    
    /// Optional notes for the reminder
    var notes: String? = nil
    
    /// The due date/time for this reminder (if any)
    var dueDate: Date? = nil
    
    /// Whether the reminder is completed
    var isCompleted: Bool = false
    
    /// When the reminder was completed (if completed)
    var completedAt: Date? = nil
    
    /// When this reminder was created
    var createdAt: Date = Date()
    
    /// When this reminder was last updated
    var updatedAt: Date = Date()
    
    /// The EventKit reminder identifier for syncing
    /// This allows us to track which Apple Reminder this corresponds to
    var eventKitReminderID: String? = nil
    
    /// The calendar identifier in EventKit that this reminder belongs to
    var eventKitCalendarID: String? = nil
    
    /// When this reminder was last synced from EventKit
    var lastSyncedAt: Date? = nil
    
    // Inverse relationship for Note.reminder
    // Note: 'notes' is a String field, so we use 'noteItems' for the relationship array
    @Relationship(deleteRule: .cascade, inverse: \Note.reminder) var noteItems: [Note]? = []
    
    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        eventKitReminderID: String? = nil,
        eventKitCalendarID: String? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.eventKitReminderID = eventKitReminderID
        self.eventKitCalendarID = eventKitCalendarID
        self.lastSyncedAt = lastSyncedAt
    }
    
    /// Mark this reminder as completed
    func markCompleted() {
        self.isCompleted = true
        self.completedAt = AppCalendar.startOfDay(Date())
        self.updatedAt = Date()
    }
    
    /// Mark this reminder as incomplete
    func markIncomplete() {
        self.isCompleted = false
        self.completedAt = nil
        self.updatedAt = Date()
    }
}


