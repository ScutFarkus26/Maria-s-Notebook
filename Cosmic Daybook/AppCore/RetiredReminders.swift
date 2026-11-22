// RetiredReminders.swift
// Takes back the reminders of features that left the app, so a device that
// still has one waiting doesn't ring for a screen that's gone.
//
// The monthly parent-report reminder ("Time for parent reports") was set up
// by Parent Reports, taken out on 2026-11-21. Its preference key stays (a
// settings backup still carries it), but nothing reads it now. Removing a
// request that isn't there does nothing, so this runs at every launch rather
// than keeping a "done once" flag.

import UserNotifications

enum RetiredReminders {
    /// The pending notification ids retired features left behind.
    static let identifiers = ["parentReports.monthly"]

    static func removePending() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
