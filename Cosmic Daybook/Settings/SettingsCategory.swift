import Foundation

// MARK: - Settings Category

/// The sidebar's six categories, one job each (regrouped 2026-09-29, ten
/// became six 2026-11-03). The cards inside each one, and what search finds
/// them by, live in `SettingsCopy.Group`. The open category is saved by raw
/// value, so a retired one is read through `init(storedValue:)`, never renamed.
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case schoolYear
    case classroom
    case lookAndFeel
    case templates
    case syncBackup
    case intelligence

    var id: String { rawValue }

    /// Raw values a selection may still hold, and the category that took each
    /// over: older builds' names, and the four retired 2026-11-03 (Overview
    /// is now the status row at the top of the list).
    static let aliases: [String: SettingsCategory] = [
        "overview": .schoolYear,
        "messages": .lookAndFeel,
        "connections": .intelligence,
        "troubleshooting": .syncBackup,
        "general": .schoolYear,
        "dataSync": .syncBackup,
        "backup": .syncBackup,
        "communication": .lookAndFeel,
        "aiFeatures": .intelligence,
        "database": .syncBackup,
        "advanced": .syncBackup
    ]

    /// The category Settings opens on when nothing usable is saved.
    static let landing: SettingsCategory = .schoolYear

    /// Reads a saved selection, including one an older build saved before the
    /// categories were regrouped.
    init?(storedValue: String) {
        guard let category = SettingsCategory(rawValue: storedValue) ?? Self.aliases[storedValue] else {
            return nil
        }
        self = category
    }

    // MARK: - Sidebar Sections

    enum Section: CaseIterable, Hashable {
        case yourClassroom
        case beyondTheNotebook

        var title: String {
            switch self {
            case .yourClassroom: return "Your classroom"
            case .beyondTheNotebook: return "Beyond the notebook"
            }
        }
    }

    var section: Section {
        switch self {
        case .schoolYear, .classroom, .lookAndFeel, .templates: return .yourClassroom
        case .syncBackup, .intelligence: return .beyondTheNotebook
        }
    }

    // MARK: - Labels

    var displayName: String {
        switch self {
        case .schoolYear: return "School year"
        case .classroom: return "Classroom"
        case .lookAndFeel: return "Look and feel"
        case .templates: return "Templates"
        case .syncBackup: return "Sync and backup"
        case .intelligence: return "Intelligence"
        }
    }

    var subtitle: String {
        switch self {
        case .schoolYear: return "Days off, year start, rollover"
        case .classroom: return "Sharing with your assistant"
        case .lookAndFeel: return "Age colors, quick capture, messages"
        case .templates: return "Meeting templates"
        case .syncBackup: return "iCloud, backups, repairs"
        case .intelligence: return "Apple Intelligence, Siri, Calendar"
        }
    }

    var icon: String {
        switch self {
        case .schoolYear: return "calendar"
        case .classroom: return "person.2.fill"
        case .lookAndFeel: return "paintpalette.fill"
        case .templates: return "doc.on.doc.fill"
        case .syncBackup: return "icloud.fill"
        case .intelligence: return "apple.intelligence"
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
