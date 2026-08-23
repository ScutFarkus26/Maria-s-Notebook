// ParentReportNotificationService.swift
// One repeating local notification on the 1st of each month, reminding the
// guide that last month's parent reports are ready to draft and send.
// No scheduler needed — due-state itself is pure ReportMonth calendar math.

import Foundation
import UserNotifications
import SwiftUI
import OSLog

@MainActor
enum ParentReportNotificationService {
    private static let notificationID = "parentReports.monthly"
    private static let logger = Logger.reports

    /// Schedules (or clears) the monthly reminder to match the settings toggle.
    static func applyPreference(enabled: Bool) async {
        if enabled {
            await scheduleMonthlyReminder()
        } else {
            cancelMonthlyReminder()
        }
    }

    static func scheduleMonthlyReminder() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                logger.notice("Parent report reminder not scheduled: notifications not authorized")
                return
            }
        } catch {
            logger.warning("Parent report reminder authorization failed: \(error.localizedDescription)")
            return
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
    }

    static func cancelMonthlyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}

// MARK: - Settings View

struct ParentReportsSettingsView: View {
    @AppStorage(UserDefaultsKeys.parentReportsReminderEnabled) private var reminderEnabled = false

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Monthly reminder") {
                Toggle("Enabled", isOn: $reminderEnabled)
                    .labelsHidden()
            }
            Text("Reminds you on the 1st of each month that last month's parent reports are ready to send.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: reminderEnabled) { _, newValue in
            SettingsCategory.markModified(.communication)
            Task { await ParentReportNotificationService.applyPreference(enabled: newValue) }
        }
        #else
        Toggle("Remind me on the 1st of each month", isOn: $reminderEnabled)
            .onChange(of: reminderEnabled) { _, newValue in
                SettingsCategory.markModified(.communication)
                Task { await ParentReportNotificationService.applyPreference(enabled: newValue) }
            }
        #endif
    }
}
