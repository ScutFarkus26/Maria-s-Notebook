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
        let identifier = response.notification.request.identifier
        guard FrontDeskEmailReminder.isReminder(identifier) else { return }
        // A reminder left over from an earlier day only opens the app: its
        // email offer would be about today (bug hunt 2026-10-20, #18).
        guard FrontDeskEmailReminder.isReminder(identifier, on: Date()) else { return }
        await MainActor.run {
            // The email offer is made on the roll, not the list.
            AttendanceScreenView.showRoll()
            AppRouter.shared.navigateTo(.attendance)
            FrontDeskEmailReminder.handleTap()
        }
    }
}
