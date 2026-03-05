import Foundation

// MARK: - Settings Category

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general
    case dataSync
    case backup
    case templates
    case communication
    case aiFeatures
    case database
    case advanced // Only shown in DEBUG builds

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .dataSync: return "Data & Sync"
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
        case .backup: return "backup restore data management export import"
        case .templates: return "templates note meeting"
        case .communication: return "communication attendance email"
        case .aiFeatures: return "ai features claude api lesson planning assistant model apple on device ollama download local"
        case .database: return "database statistics records overview storage"
        case .advanced: return "advanced debug test students"
        }
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
