import Foundation

// MARK: - Settings Copy

/// The one name for every card Settings shows, and the words search finds it by.
///
/// A pane builds its cards from these (`SettingsGroup(.iCloud) { … }`) and the
/// sidebar's search reads the same list, so a card's title and its search entry
/// can't drift apart. When a card gains a control, add the control's label to
/// that card's `keywords`.
enum SettingsCopy {

    enum Group: String, CaseIterable, Identifiable, Hashable {
        // School year
        case schoolYearStart
        case daysOff
        case newYear
        // Classroom
        case classroomSharing
        // Look and feel
        case ageIndicators
        case quickCapture
        // Messages
        case attendanceEmail
        case parentReports
        case orderRequests
        // Templates
        case noteTemplates
        case meetingTemplates
        case todoTemplates
        // Connections
        case appleCalendar
        case reminders
        case claudeDesktop
        // Intelligence
        case appleIntelligence
        case lessonPlanning
        case siri
        // Sync and backup
        case iCloud
        case backups
        case settingsTransfer
        // Troubleshooting
        case syncHistory
        case maintenance
        case notebookStats
        case testStudents

        var id: String { rawValue }

        /// The scroll target search jumps to.
        var anchorID: String { "settings.group.\(rawValue)" }

        var category: SettingsCategory {
            switch self {
            case .schoolYearStart, .daysOff, .newYear: return .schoolYear
            case .classroomSharing: return .classroom
            case .ageIndicators, .quickCapture: return .lookAndFeel
            case .attendanceEmail, .parentReports, .orderRequests: return .messages
            case .noteTemplates, .meetingTemplates, .todoTemplates: return .templates
            case .appleCalendar, .reminders, .claudeDesktop: return .connections
            case .appleIntelligence, .lessonPlanning, .siri: return .intelligence
            case .iCloud, .backups, .settingsTransfer: return .syncBackup
            case .syncHistory, .maintenance, .notebookStats, .testStudents: return .troubleshooting
            }
        }

        var title: String {
            switch self {
            case .schoolYearStart: return "School year"
            case .daysOff: return "Days off"
            case .newYear: return "New year"
            case .classroomSharing: return "Classroom sharing"
            case .ageIndicators: return "Age indicators"
            case .quickCapture: return "Quick capture"
            case .attendanceEmail: return "Attendance email"
            case .parentReports: return "Parent reports"
            case .orderRequests: return "Order requests"
            case .noteTemplates: return "Note templates"
            case .meetingTemplates: return "Meeting templates"
            case .todoTemplates: return "To-do templates"
            case .appleCalendar: return "Apple Calendar events"
            case .reminders: return "Reminders"
            case .claudeDesktop: return "Claude Desktop"
            case .appleIntelligence: return "Apple Intelligence"
            case .lessonPlanning: return "Lesson planning"
            case .siri: return "Siri and Shortcuts"
            case .iCloud: return "iCloud"
            case .backups: return "Backups"
            case .settingsTransfer: return "Move settings to another device"
            case .syncHistory: return "Sync history"
            case .maintenance: return "If sync gets stuck"
            case .notebookStats: return "Notebook at a glance"
            case .testStudents: return "Test students"
            }
        }

        var systemImage: String {
            switch self {
            case .schoolYearStart: return "calendar.badge.clock"
            case .daysOff: return "calendar"
            case .newYear: return "sparkles"
            case .classroomSharing: return "person.2.fill"
            case .ageIndicators: return "paintpalette.fill"
            case .quickCapture: return "plus.circle.fill"
            case .attendanceEmail: return "checkmark.circle.fill"
            case .parentReports: return "envelope.badge.person.crop"
            case .orderRequests: return "cart.fill"
            case .noteTemplates: return "note.text.badge.plus"
            case .meetingTemplates: return "person.2.wave.2.fill"
            case .todoTemplates: return "checklist"
            case .appleCalendar: return "calendar.day.timeline.left"
            case .reminders: return "bell.fill"
            case .claudeDesktop: return "desktopcomputer"
            case .appleIntelligence: return "apple.intelligence"
            case .lessonPlanning: return "list.clipboard"
            case .siri: return "mic.fill"
            case .iCloud: return "icloud.fill"
            case .backups: return "externaldrive.fill"
            case .settingsTransfer: return "arrow.left.arrow.right"
            case .syncHistory: return "clock.arrow.circlepath"
            case .maintenance: return "wrench.and.screwdriver.fill"
            case .notebookStats: return "chart.bar.xaxis"
            case .testStudents: return "person.2.slash"
            }
        }

        /// Other words a guide might search for to reach this card: the labels of its controls.
        var keywords: [String] {
            switch self {
            case .schoolYearStart:
                return ["School calendar", "Year start", "School year start", "Day counters"]
            case .daysOff:
                return ["School calendar", "Non-school days", "Holidays", "Clear this month"]
            case .newYear:
                return ["School calendar", "School year rollover", "Rollover", "Carried-over year plans",
                        "Grade guidelines", "Florida"]
            case .classroomSharing:
                return ["Your assistant", "Assistant", "Members", "Set up classroom sharing",
                        "Manage sharing", "Stop sharing", "Leave classroom", "Invite", "Share"]
            case .ageIndicators:
                return ["Lesson age", "Work age", "Warn after", "Overdue after",
                        "Colors", "Fresh color", "Warning color", "Overdue color", "School days", "Reset to defaults"]
            case .quickCapture:
                return ["Floating button", "Show the floating button", "Pie menu", "Quick actions"]
            case .attendanceEmail:
                return ["Email", "Send to", "From", "Name order", "Group by level", "Front desk", "Deadline", "Remind me"]
            case .parentReports:
                return ["Monthly reminder", "Reports"]
            case .orderRequests:
                return ["Orders", "Office", "Send requests to", "Sign off"]
            case .noteTemplates:
                return ["Templates", "Observations"]
            case .meetingTemplates:
                return ["Templates", "Meetings", "Prompts"]
            case .todoTemplates:
                return ["Templates", "To-dos", "Todos"]
            case .appleCalendar:
                return ["Calendar", "Calendars", "Events", "Today"]
            case .reminders:
                return ["Reminders list", "Sync from list", "Today"]
            case .claudeDesktop:
                return ["Claude", "MCP", "Anthropic", "Allow Claude Desktop access"]
            case .appleIntelligence:
                return ["AI", "On this device", "On-device", "Private Cloud Compute", "Private Cloud",
                        "Allow Private Cloud Compute"]
            case .lessonPlanning:
                return ["Depth", "Quick", "Standard", "Deep", "Planning assistant"]
            case .siri:
                return ["Siri", "Shortcuts", "Voice", "Attendance by voice", "Undo attendance",
                        "Log an observation", "Mark presented"]
            case .iCloud:
                return ["Sync", "Sync now", "iCloud sync", "Sync with iCloud", "Last synced"]
            case .backups:
                return ["Backup", "Back up now", "Restore", "Merge", "Replace", "Automatic backups",
                        "Keep", "Include note photos", "Backup folder", "Back up every",
                        "Restore last automatic backup", "How to restore"]
            case .settingsTransfer:
                return ["Export settings", "Import settings", "Settings profile", "Settings file", "New device"]
            case .syncHistory:
                return ["Sync", "Sync details", "Sync problems", "Send changes now", "Errors", "Conflicts"]
            case .maintenance:
                return ["Reset local cache", "Re-download from iCloud", "Maintenance", "Repair"]
            case .notebookStats:
                return ["Records", "Statistics", "Database", "Counts", "Students", "Lessons", "Presentations",
                        "Orders", "Album marks", "Stories", "Going-outs", "Supply history"]
            case .testStudents:
                return ["Show test students", "Debug"]
            }
        }

        /// Whether this build shows the card: Claude Desktop is Mac-only, test students debug-only.
        var isAvailable: Bool {
            switch self {
            case .claudeDesktop:
                #if os(macOS)
                return true
                #else
                return false
                #endif
            case .testStudents:
                #if DEBUG
                return true
                #else
                return false
                #endif
            default:
                return true
            }
        }

        /// Case- and diacritic-insensitive match on the title or any keyword.
        func matches(_ query: String) -> Bool {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return ([title] + keywords).contains { $0.localizedStandardContains(query) }
        }
    }
}
