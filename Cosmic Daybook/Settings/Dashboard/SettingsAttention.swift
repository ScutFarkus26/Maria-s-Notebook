import EventKit
import Foundation

// MARK: - Settings Attention

/// One thing the Overview asks the guide to look at, with where its fix lives.
enum SettingsAttentionItem: Hashable, Identifiable {
    /// iCloud reports an error (`isError`) or is running behind.
    case syncProblem(isError: Bool)
    /// No backup from this device for a week or more (nil days: never), or
    /// this device's automatic backups failing (`failing`). One row either
    /// way, fixed the same way: Back up now, run in place, whose own failure
    /// shows under the row.
    case backupDue(daysSinceLastBackup: Int?, failing: AutomaticBackupFailure? = nil)
    /// Classroom records the lead guide owns that aren't in the classroom share.
    case unsharedClassroomRecords(Int)
    /// Year-plan targets left over from a school year that has ended.
    case carriedOverPlans(Int)
    /// Apple Calendar or Reminders was set up, and access has since been turned off.
    case connectionAccessLost

    var id: String {
        switch self {
        case .syncProblem: return "sync"
        case .backupDue: return "backup"
        case .unsharedClassroomRecords: return "classroom"
        case .carriedOverPlans: return "carriedOver"
        case .connectionAccessLost: return "connections"
        }
    }

    /// The category whose pane holds the fix. Nil for a backup, which the
    /// Overview runs in place.
    var destination: SettingsCategory? {
        switch self {
        case .syncProblem: return .syncBackup
        case .backupDue: return nil
        case .unsharedClassroomRecords: return .classroom
        case .carriedOverPlans: return .schoolYear
        case .connectionAccessLost: return .connections
        }
    }

    /// The card inside `destination` to scroll to and outline, when there is one.
    var focus: SettingsCopy.Group? {
        switch self {
        case .syncProblem: return .iCloud
        case .unsharedClassroomRecords: return .classroomSharing
        case .carriedOverPlans: return .newYear
        case .backupDue, .connectionAccessLost: return nil
        }
    }

    // MARK: Copy

    var title: String {
        switch self {
        case .syncProblem(let isError):
            return isError ? "iCloud sync has a problem" : "iCloud sync is running behind"
        case .backupDue(_, let failing?):
            return failing.title
        case .backupDue(let days, nil):
            guard let days else { return "No backup yet" }
            return "Last backup was \(days) \(days == 1 ? "day" : "days") ago"
        case .unsharedClassroomRecords(let count):
            return count == 1
                ? "1 classroom item isn't shared with your assistant yet"
                : "\(count) classroom items aren't shared with your assistant yet"
        case .carriedOverPlans(let count):
            return count == 1 ? "1 year-plan target carried over" : "\(count) year-plan targets carried over"
        case .connectionAccessLost:
            return "Apple Calendar access is off"
        }
    }

    var detail: String {
        switch self {
        case .syncProblem(let isError):
            return isError
                ? "Recent changes may not have reached your other devices yet."
                : "Changes are taking longer than usual to reach your other devices."
        case .backupDue(_, .some):
            return "Back up now so there's a fresh copy. If that doesn't work either, the reason shows here."
        case .backupDue(let days, nil):
            return days == nil
                ? "Make one now so there's always a copy of your notebook to go back to."
                : "A fresh one keeps this week's work safe."
        case .unsharedClassroomRecords(let count):
            return count == 1
                ? "Your assistant can't see it. Add it to the share in Classroom."
                : "Your assistant can't see them. Add them to the share in Classroom."
        case .carriedOverPlans(let count):
            return count == 1
                ? "It's left from a school year that has ended. Re-date or skip it in School year."
                : "They're left from a school year that has ended. Re-date or skip them in School year."
        case .connectionAccessLost:
            #if os(macOS)
            return "Turn access back on in System Settings › Privacy & Security."
            #else
            return "Turn access back on in Settings › Privacy & Security."
            #endif
        }
    }

    var systemImage: String {
        switch self {
        case .syncProblem(let isError): return isError ? "xmark.icloud" : "exclamationmark.icloud"
        case .backupDue: return "externaldrive.badge.exclamationmark"
        case .unsharedClassroomRecords: return "person.2.slash"
        case .carriedOverPlans: return "calendar.badge.exclamationmark"
        case .connectionAccessLost: return "hand.raised.slash"
        }
    }

    /// The fix button's label.
    var actionTitle: String {
        switch self {
        case .syncProblem: return "Open Sync and backup"
        case .backupDue: return "Back up now"
        case .unsharedClassroomRecords: return "Open Classroom"
        case .carriedOverPlans: return "Review"
        case .connectionAccessLost: return "Open Connections"
        }
    }
}

/// This device's automatic backups failing since `since`
/// (`AutoBackupManager.automaticBackupFailingSince`), worded for `device`
/// ("Mac", "iPad", "iPhone").
struct AutomaticBackupFailure: Hashable {
    let device: String
    let since: Date
    /// Whether `since` is today, worded "didn't work" rather than "since".
    var isToday = false

    var title: String {
        isToday
            ? "This \(device)'s last automatic backup didn't work"
            : "This \(device)'s automatic backups haven't worked since "
                + since.formatted(date: .long, time: .omitted)
    }
}

/// What the Overview knows when it decides which rows to show. Nil counts
/// mean "doesn't apply here" (not the lead guide, sharing not set up, the
/// sweep already run this year) or "not read yet".
struct SettingsAttentionInputs {
    /// This device's last backup: one it wrote itself, by hand or
    /// automatically. Another device's backups don't count, or a Mac that
    /// backs up hid an iPad that hadn't for weeks (bug hunt 2026-11-02 #12).
    var lastBackup: Date?
    /// When this device's automatic backups started failing; nil while they
    /// work, or when they're off.
    var automaticBackupFailingSince: Date?
    /// What this device is called in the failing row.
    var deviceKind = "device"
    var syncHealth: CloudKitHealthCheck.SyncHealth = .unknown
    var unsharedClassroomRecords: Int?
    var carriedOverPlans: Int?
    var calendarAccessLost = false
}

/// Decides which "Needs your attention" rows the Overview shows. Pure, so the
/// rules are tested without a view.
enum SettingsAttention {
    /// A backup this many days old, or older, asks for a fresh one.
    static let backupStaleAfterDays = 7

    /// The rows that apply, most urgent first: sync, backup, sharing, year
    /// plans, connections. Empty means all set.
    static func items(
        for inputs: SettingsAttentionInputs,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) -> [SettingsAttentionItem] {
        var items: [SettingsAttentionItem] = []

        switch inputs.syncHealth {
        case .error: items.append(.syncProblem(isError: true))
        case .warning: items.append(.syncProblem(isError: false))
        case .healthy, .syncing, .offline, .unknown: break
        }

        let days = inputs.lastBackup.map { daysSince($0, now: now, calendar: calendar) }
        if let failingSince = inputs.automaticBackupFailingSince {
            items.append(.backupDue(daysSinceLastBackup: days, failing: AutomaticBackupFailure(
                device: inputs.deviceKind,
                since: failingSince,
                isToday: calendar.isDate(failingSince, inSameDayAs: now)
            )))
        } else if let days {
            if days >= backupStaleAfterDays {
                items.append(.backupDue(daysSinceLastBackup: days))
            }
        } else {
            items.append(.backupDue(daysSinceLastBackup: nil))
        }

        if let unshared = inputs.unsharedClassroomRecords, unshared > 0 {
            items.append(.unsharedClassroomRecords(unshared))
        }

        if let carriedOver = inputs.carriedOverPlans, carriedOver > 0 {
            items.append(.carriedOverPlans(carriedOver))
        }

        if inputs.calendarAccessLost {
            items.append(.connectionAccessLost)
        }

        return items
    }

    /// Whole days from `date` to `now`, never negative.
    static func daysSince(_ date: Date, now: Date, calendar: Calendar = AppCalendar.shared) -> Int {
        max(0, calendar.dateComponents([.day], from: date, to: now).day ?? 0)
    }

    /// A connection the guide set up (which took granting access) whose
    /// access is now off or reduced to adding only, so the app can't read it.
    static func accessLost(configured: Bool, status: EKAuthorizationStatus) -> Bool {
        guard configured else { return false }
        switch status {
        case .denied, .restricted, .writeOnly: return true
        case .fullAccess, .notDetermined: return false
        @unknown default: return false
        }
    }
}
