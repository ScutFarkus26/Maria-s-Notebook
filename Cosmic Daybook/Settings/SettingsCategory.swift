import Foundation

// MARK: - Settings Category

/// The sidebar's categories, one job each (regrouped 2026-09-29). The cards
/// inside each one, and what search finds them by, live in `SettingsCopy.Group`.
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case overview
    case schoolYear
    case classroom
    case lookAndFeel
    case messages
    case templates
    case connections
    case intelligence
    case syncBackup
    case troubleshooting

    var id: String { rawValue }

    /// Reads a saved selection, including one an older build saved before the
    /// categories were regrouped.
    init?(storedValue: String) {
        if let category = SettingsCategory(rawValue: storedValue) {
            self = category
            return
        }
        switch storedValue {
        case "general": self = .schoolYear
        case "dataSync", "backup": self = .syncBackup
        case "communication": self = .messages
        case "aiFeatures": self = .intelligence
        case "database", "advanced": self = .troubleshooting
        default: return nil
        }
    }

    // MARK: - Sidebar Sections

    enum Section: CaseIterable, Hashable {
        case top
        case yourClassroom
        case beyondTheNotebook
        case bottom

        var title: String? {
            switch self {
            case .yourClassroom: return "Your classroom"
            case .beyondTheNotebook: return "Beyond the notebook"
            case .top, .bottom: return nil
            }
        }
    }

    var section: Section {
        switch self {
        case .overview: return .top
        case .schoolYear, .classroom, .lookAndFeel, .messages, .templates: return .yourClassroom
        case .connections, .intelligence, .syncBackup: return .beyondTheNotebook
        case .troubleshooting: return .bottom
        }
    }

    // MARK: - Labels

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .schoolYear: return "School year"
        case .classroom: return "Classroom"
        case .lookAndFeel: return "Look and feel"
        case .messages: return "Messages"
        case .templates: return "Templates"
        case .connections: return "Connections"
        case .intelligence: return "Intelligence"
        case .syncBackup: return "Sync and backup"
        case .troubleshooting: return "Troubleshooting"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "What needs you, and what's new"
        case .schoolYear: return "Days off, year start, rollover"
        case .classroom: return "Sharing with your assistant"
        case .lookAndFeel: return "Age colors, quick capture"
        case .messages: return "Attendance email, parent reports, orders"
        case .templates: return "Note, meeting and to-do templates"
        case .connections:
            #if os(macOS)
            return "Calendar, Reminders, Claude Desktop"
            #else
            return "Calendar and Reminders"
            #endif
        case .intelligence: return "Apple Intelligence and Siri"
        case .syncBackup: return "iCloud, backups, moving settings"
        case .troubleshooting: return "Sync history and repairs"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "sparkles"
        case .schoolYear: return "calendar"
        case .classroom: return "person.2.fill"
        case .lookAndFeel: return "paintpalette.fill"
        case .messages: return "envelope.fill"
        case .templates: return "doc.on.doc.fill"
        case .connections: return "app.connected.to.app.below.fill"
        case .intelligence: return "apple.intelligence"
        case .syncBackup: return "icloud.fill"
        case .troubleshooting: return "lifepreserver.fill"
        }
    }

    // MARK: - Search

    /// The cards this build shows in the category.
    var groups: [SettingsCopy.Group] {
        SettingsCopy.Group.allCases.filter { $0.category == self && $0.isAvailable }
    }

    /// Case- and diacritic-insensitive match on the category's name or any of its cards.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if displayName.localizedStandardContains(query) || subtitle.localizedStandardContains(query) {
            return true
        }
        return groups.contains { $0.matches(query) }
    }

    static var visibleCategories: [SettingsCategory] { allCases }
}
