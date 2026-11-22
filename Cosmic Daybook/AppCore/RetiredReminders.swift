// RetiredReminders.swift
// Takes back the reminders of features that left the app, so a device that
// still has one waiting doesn't ring for a screen that's gone.
//
// The monthly parent-report reminder ("Time for parent reports") was set up
// by Parent Reports, taken out on 2026-11-21. Its preference key stays (a
// settings backup still carries it), but nothing reads it now. Removing a
// request that isn't there does nothing, so this runs at every launch rather
// than keeping a "done once" flag. It clears both the waiting request and a
// copy already delivered to Notification Center, which stays there until the
// person swipes it away (removing the request alone leaves that one).

import UserNotifications

/// The two things the retired reminders are taken back with. `UNUserNotificationCenter`
/// is the real one; a test passes its own to see the calls.
protocol RetiredReminderRemoving {
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: RetiredReminderRemoving {}

enum RetiredReminders {
    /// The notification ids retired features left behind.
    static let identifiers = ["parentReports.monthly"]

    /// Takes back every retired reminder: the one still waiting to ring and the one already delivered.
    static func removePending(from center: some RetiredReminderRemoving = UNUserNotificationCenter.current()) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
