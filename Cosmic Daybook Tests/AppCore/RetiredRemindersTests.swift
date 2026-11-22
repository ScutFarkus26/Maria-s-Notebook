import Foundation
import Testing
@testable import CosmicDaybook

/// The reminder of a taken-out feature is cleared both ways: the request still
/// waiting and the notification already sitting in Notification Center.
@Suite("Retired reminders")
struct RetiredRemindersTests {

    private final class RecordingCenter: RetiredReminderRemoving {
        var pending: [[String]] = []
        var delivered: [[String]] = []
        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { pending.append(identifiers) }
        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) { delivered.append(identifiers) }
    }

    @Test("The monthly parent-report reminder is taken back, waiting and delivered")
    func clearsPendingAndDelivered() {
        let center = RecordingCenter()
        RetiredReminders.removePending(from: center)
        #expect(RetiredReminders.identifiers == ["parentReports.monthly"])
        #expect(center.pending == [RetiredReminders.identifiers])
        #expect(center.delivered == [RetiredReminders.identifiers])
    }
}
