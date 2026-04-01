import Foundation

// MARK: - Settings Category

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general
    case dataSync
    case classroom
    case backup
    case templates
    case communication
    case aiFeatures
    case database
    case advanced // Only shown in DEBUG builds

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .general: return "School calendar, display & colors"
        case .dataSync: return "iCloud, Reminders, Calendar"
        case .classroom: return "Sharing, roles & members"
        case .backup: return "Export, restore & auto-backup"
        case .templates: return "CDNote & meeting templates"
        case .communication: return "Attendance email settings"
        case .aiFeatures: return "Claude, Ollama & Apple AI"
        case .database: return "Record counts & statistics"
        case .advanced: return "Testing & debug tools"
        }
    }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .dataSync: return "Data & Sync"
        case .classroom: return "Classroom"
        case .backup: return "Backup"
        case .templates: return "Templates"
        case .communication: return "Communication"
        case .aiFeatures: return "AI & Models"
        case .database: return "Database"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .dataSync: return "arrow.triangle.2.circlepath"
        case .classroom: return "person.2.badge.gearshape.fill"
        case .backup: return "externaldrive.fill"
        case .templates: return "doc.on.doc.fill"
        case .communication: return "envelope.fill"
        case .aiFeatures: return "brain.head.profile"
        case .database: return "cylinder.fill"
        case .advanced: return "wrench.and.screwdriver.fill"
        }
    }

    var searchKeywords: String {
        switch self {
        case .general: return "general school calendar display colors lesson age work age"
        case .dataSync: return "data sync icloud reminders calendar"
        case .classroom: return "classroom sharing invite assistant guide role members"
        case .backup: return "backup restore data management export import"
        case .templates: return "templates note meeting"
        case .communication: return "communication attendance email"
        case .aiFeatures:
            return "ai features claude api lesson planning assistant model apple on device ollama download local"
        case .database: return "database statistics records overview storage"
        case .advanced: return "advanced debug test students"
        }
    }

    /// Detailed setting labels within each category for deep search
    var detailedSettings: [String] {
        switch self {
        case .general:
            return [
                "School Calendar", "Non-School Days", "Clear Month", "Keep Weekends Only",
                "Display & Colors", "CDLesson Age Indicators", "Warning Days", "Overdue Days",
                "Fresh Color", "Warning Color", "Overdue Color",
                "Work Age Indicators"
            ]
        case .dataSync:
            return [
                "iCloud", "CloudKit", "Sync Now", "Last Synced", "Enable iCloud Backup",
                "Reminders", "CDReminder List", "Request Access", "Sync Reminders",
                "Calendar", "Calendar Events", "Refresh Calendars"
            ]
        case .classroom:
            return [
                "Share Classroom", "Participants", "Your Role",
                "Leave Classroom", "Invite Assistant"
            ]
        case .backup:
            return [
                "Create Backup", "Encrypted", "Restore", "Merge", "Replace",
                "Import", "Storage", "Choose Folder", "Auto-Backup", "Retention"
            ]
        case .templates:
            return [
                "CDNote Templates", "Meeting Templates", "Manage Templates"
            ]
        case .communication:
            return [
                "Attendance Email", "Email To", "Email From", "Enable Email"
            ]
        case .aiFeatures:
            return [
                "AI Models", "Chat Model", "CDLesson Planning Model", "Background Tasks Model",
                "Apple Intelligence", "On-Device", "Ollama", "Server URL", "Model",
                "Install Models", "Pull Model", "Claude API Key", "Anthropic",
                "Configure API Key", "Sonnet", "Haiku", "Test Connection",
                "CDLesson Planning Assistant", "Depth", "System Prompt", "Temperature", "Timeout",
                "API Usage", "Estimated Cost"
            ]
        case .database:
            return [
                "Total Records", "Students", "Lessons", "Lessons Planned", "Lessons Given",
                "Work Items", "Presentations", "Observations", "Meetings", "Practice",
                "To-Do Items", "Reminders", "Tracks", "Calendar Events", "Projects",
                "Attendance", "Supplies", "Issues", "Community", "Procedures",
                "Documents", "CDLesson Files", "Templates", "Dev Snapshots"
            ]
        case .advanced:
            return [
                "Test Students", "Show Test Students", "Test CDStudent Names"
            ]
        }
    }

    // MARK: - Recently Changed Tracking

    var lastModifiedKey: String {
        "Settings.lastModified.\(rawValue)"
    }

    var wasRecentlyModified: Bool {
        let timestamp = UserDefaults.standard.double(forKey: lastModifiedKey)
        guard timestamp > 0 else { return false }
        let lastModified = Date(timeIntervalSinceReferenceDate: timestamp)
        return Date().timeIntervalSince(lastModified) < 86400 // 24 hours
    }

    static func markModified(_ category: SettingsCategory) {
        UserDefaults.standard.set(
            Date().timeIntervalSinceReferenceDate,
            forKey: category.lastModifiedKey
        )
    }

    /// Categories visible in the UI (excludes advanced in release builds)
    static var visibleCategories: [SettingsCategory] {
        #if DEBUG
        return allCases
        #else
        return allCases.filter { $0 != .advanced }
        #endif
    }
}
