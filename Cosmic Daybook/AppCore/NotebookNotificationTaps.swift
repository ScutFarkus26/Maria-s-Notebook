import Foundation
import UserNotifications

/// The notebook's notification delegate. A reminder that fires while the app
/// is open still shows, and a tapped front-desk email reminder opens
/// Attendance with today's email ready (`FrontDeskEmailReminder`). Every
/// other notification opens the app as before.
final class NotebookNotificationTaps: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotebookNotificationTaps()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard FrontDeskEmailReminder.isReminder(response.notification.request.identifier) else { return }
        await MainActor.run {
            AppRouter.shared.navigateTo(.attendance)
            FrontDeskEmailReminder.handleTap()
        }
    }
}
