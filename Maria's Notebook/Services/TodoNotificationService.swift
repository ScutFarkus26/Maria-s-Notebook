import Foundation
import UserNotifications
import CoreData
import OSLog

/// Service for managing todo notifications and reminders
@MainActor
class TodoNotificationService {
    private static let logger = Logger.todos
    static let shared = TodoNotificationService()

    private init() {}

    /// Request notification permissions
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            Self.logger.error("Failed to request notification authorization: \(error, privacy: .public)")
            return false
        }
    }

    /// Check current notification authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Core Data Notification Methods

    /// Schedule a notification for a Core Data todo item
    func scheduleNotification(for todo: CDTodoItemEntity, at date: Date, context: NSManagedObjectContext) async throws {
        // Cancel any existing notification
        if let existingID = todo.notificationID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [existingID])
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Todo CDReminder"
        content.body = todo.title
        content.sound = .default

        // Add tag info as subtitle if available
        if let tags = todo.tags as? [String], let firstTag = tags.first {
            content.subtitle = TodoTagHelper.tagName(firstTag)
        }

        // Set user info for handling notification tap
        if let id = todo.id {
            content.userInfo = ["todoID": id.uuidString]
        }

        // Create trigger from date
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // Create unique identifier
        let identifier = "todo-\(todo.id?.uuidString ?? UUID().uuidString)"

        // Create and add request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)

        // Update todo with notification ID
        todo.notificationID = identifier
        todo.reminderDate = date
        context.safeSave()
    }

    /// Cancel scheduled notification for a Core Data todo
    func cancelNotification(for todo: CDTodoItemEntity, context: NSManagedObjectContext) {
        guard let notificationID = todo.notificationID else { return }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])

        todo.notificationID = nil
        todo.reminderDate = nil
        context.safeSave()
    }

    /// Reschedule notification if reminder date changes (Core Data)
    func rescheduleNotification(for todo: CDTodoItemEntity, newDate: Date, context: NSManagedObjectContext) async throws {
        try await scheduleNotification(for: todo, at: newDate, context: context)
    }

    // MARK: - Helper Methods

    /// Get all pending notifications for debugging
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
}
