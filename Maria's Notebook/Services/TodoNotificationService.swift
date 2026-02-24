import Foundation
import UserNotifications
import SwiftData

/// Service for managing todo notifications and reminders
@MainActor
class TodoNotificationService {
    static let shared = TodoNotificationService()
    
    private init() {}
    
    /// Request notification permissions
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            print("Error requesting notification authorization: \(error)")
            return false
        }
    }
    
    /// Check current notification authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    /// Schedule a notification for a todo item
    func scheduleNotification(for todo: TodoItem, at date: Date) async throws {
        // Cancel any existing notification
        if let existingID = todo.notificationID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [existingID])
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Todo Reminder"
        content.body = todo.title
        content.sound = .default
        
        // Add tag info as subtitle if available
        if let firstTag = todo.tags.first {
            content.subtitle = TodoTagHelper.tagName(firstTag)
        }
        
        // Set user info for handling notification tap
        content.userInfo = ["todoID": todo.id.uuidString]
        
        // Create trigger from date
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // Create unique identifier
        let identifier = "todo-\(todo.id.uuidString)"
        
        // Create and add request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
        
        // Update todo with notification ID
        todo.notificationID = identifier
        todo.reminderDate = date

        if let context = todo.modelContext {
            safeSave(context: context, contextName: "scheduleNotification")
        }
    }
    
    /// Cancel scheduled notification for a todo
    func cancelNotification(for todo: TodoItem) {
        guard let notificationID = todo.notificationID else { return }
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        
        todo.notificationID = nil
        todo.reminderDate = nil

        if let context = todo.modelContext {
            safeSave(context: context, contextName: "cancelNotification")
        }
    }

    // MARK: - Helper Methods

    private func safeSave(context: ModelContext, contextName: String = #function) {
        do {
            try context.save()
        } catch {
            print("⚠️ [\(contextName)] Failed to save: \(error)")
        }
    }
    
    /// Get all pending notifications for debugging
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
    
    /// Reschedule notification if reminder date changes
    func rescheduleNotification(for todo: TodoItem, newDate: Date) async throws {
        try await scheduleNotification(for: todo, at: newDate)
    }
}
