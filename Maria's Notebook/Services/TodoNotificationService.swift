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

    // MARK: - Initiative Deadline Notifications

    /// Default lead-time days for new initiatives (overridable per-initiative).
    /// Stored as `[Int]` array of days before the deadline, fired at 09:00 local.
    static var defaultInitiativeLeadTimeDays: [Int] {
        get {
            if let raw = UserDefaults.standard.array(forKey: "Initiative.defaultLeadTimeDays") as? [Int],
               !raw.isEmpty {
                return raw
            }
            return [7, 3, 1, 0]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Initiative.defaultLeadTimeDays")
        }
    }

    /// Pick lead times for an initiative: per-initiative override if present, else the global default.
    private func effectiveLeadTimes(for initiative: CDInitiative) -> [Int] {
        let perInitiative = initiative.leadTimeDaysArray
        if !perInitiative.isEmpty { return perInitiative }
        return Self.defaultInitiativeLeadTimeDays
    }

    /// Schedule all reminder notifications for an Initiative's deadline.
    /// Skips lead times that are already in the past.
    func scheduleNotifications(for initiative: CDInitiative, context: NSManagedObjectContext) async throws {
        // Always clear pending IDs first so a re-schedule cleans up stale ones.
        cancelNotifications(for: initiative, context: context)

        guard let deadline = initiative.deadline,
              !initiative.isCompleted,
              let uuidString = initiative.id?.uuidString else { return }

        let leadTimes = effectiveLeadTimes(for: initiative)
        var scheduledIDs: [String] = []

        for leadDays in leadTimes {
            guard let triggerDate = computeLeadTimeFireDate(deadline: deadline, leadDays: leadDays),
                  triggerDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Initiative due soon"
            content.body = bodyText(for: initiative, leadDays: leadDays)
            content.sound = .default
            content.userInfo = ["initiativeID": uuidString]

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let identifier = "initiative-\(uuidString)-\(leadDays)d"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            do {
                try await UNUserNotificationCenter.current().add(request)
                scheduledIDs.append(identifier)
            } catch {
                Self.logger.error("Failed to schedule initiative notification \(identifier, privacy: .public): \(error, privacy: .public)")
            }
        }

        initiative.notificationIDsArray = scheduledIDs
        initiative.modifiedAt = Date()
        context.safeSave()
    }

    /// Cancel all pending notifications for an Initiative and clear its `notificationIDs`.
    func cancelNotifications(for initiative: CDInitiative, context: NSManagedObjectContext) {
        let ids = initiative.notificationIDsArray
        if !ids.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            initiative.notificationIDsArray = []
            context.safeSave()
        }
    }

    /// Cancel + schedule. Use whenever an initiative's deadline or lead times change.
    func rescheduleNotifications(for initiative: CDInitiative, context: NSManagedObjectContext) async throws {
        try await scheduleNotifications(for: initiative, context: context)
    }

    private func computeLeadTimeFireDate(deadline: Date, leadDays: Int) -> Date? {
        let cal = Calendar.current
        let startOfDeadline = cal.startOfDay(for: deadline)
        guard let target = cal.date(byAdding: .day, value: -leadDays, to: startOfDeadline) else { return nil }
        // Fire at 09:00 local.
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: target)
    }

    private func bodyText(for initiative: CDInitiative, leadDays: Int) -> String {
        let title = initiative.title.isEmpty ? "Untitled initiative" : initiative.title
        switch leadDays {
        case 0:   return "\(title) is due today"
        case 1:   return "\(title) is due tomorrow"
        default:  return "\(title) is due in \(leadDays) days"
        }
    }

    // MARK: - Helper Methods

    /// Get all pending notifications for debugging
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
}
