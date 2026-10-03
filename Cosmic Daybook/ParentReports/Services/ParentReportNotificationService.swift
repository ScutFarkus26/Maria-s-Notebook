// ParentReportNotificationService.swift
// One repeating local notification on the 1st of each month, reminding the
// guide that last month's parent reports are ready to draft and send.
// No scheduler needed — due-state itself is pure ReportMonth calendar math.

import Foundation
import UserNotifications
import SwiftUI
import OSLog

enum ParentReportNotificationService {
    private static let notificationID = "parentReports.monthly"
    private static let logger = Logger.reports

    /// Schedules (or clears) the monthly reminder to match the settings toggle.
    /// Returns false when the reminder is on but notifications aren't allowed,
    /// so it can't show.
    @discardableResult
    static func applyPreference(enabled: Bool) async -> Bool {
        if enabled {
            return await scheduleMonthlyReminder()
        }
        cancelMonthlyReminder()
        return true
    }

    /// Whether notifications for the app have been turned off, without
    /// asking for them.
    static func notificationsDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Returns false when notifications aren't allowed, so nothing was scheduled.
    @discardableResult
    static func scheduleMonthlyReminder() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                logger.notice("Parent report reminder not scheduled: notifications not authorized")
                return false
            }
        } catch {
            logger.warning("Parent report reminder authorization failed: \(error.localizedDescription)")
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Monthly parent reports"
        content.body = "Last month's progress reports are ready to draft, review, and send."
        content.sound = .default

        var components = DateComponents()
        components.day = 1
        components.hour = 8
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)

        // Replace any prior registration so the schedule stays single.
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        do {
            try await center.add(request)
        } catch {
            logger.warning("Failed to schedule parent report reminder: \(error.localizedDescription)")
        }
        return true
    }

    static func cancelMonthlyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}

// MARK: - Settings View

struct ParentReportsSettingsView: View {
    @AppStorage(UserDefaultsKeys.parentReportsReminderEnabled) private var reminderEnabled = false
    /// The reminder is on but notifications are off, so it can't show: said
    /// under the toggle, rather than leaving it on as if it worked.
    @State private var notificationsDenied = false

    var body: some View {
        content
            .task {
                guard reminderEnabled else { return }
                notificationsDenied = await ParentReportNotificationService.notificationsDenied()
            }
            .onChange(of: reminderEnabled) { _, newValue in
                Task {
                    let canShow = await ParentReportNotificationService.applyPreference(enabled: newValue)
                    notificationsDenied = !canShow
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Monthly reminder") {
                Toggle("Enabled", isOn: $reminderEnabled)
                    .labelsHidden()
            }
            Text("Reminds you on the 1st of each month that last month's parent reports are ready to send.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            deniedFootnote
        }
        #else
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Remind me on the 1st of each month", isOn: $reminderEnabled)
            deniedFootnote
        }
        #endif
    }

    @ViewBuilder
    private var deniedFootnote: some View {
        if reminderEnabled && notificationsDenied {
            Text("Notifications are off for Cosmic Daybook, so this reminder can't show. "
                + "Turn them on in \(SystemSettingsApp.name) › Notifications.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
