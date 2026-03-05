import Foundation

// MARK: - Settings Export Service

/// Exports and imports app settings as a JSON profile.
/// IMPORTANT: Never exports API keys, passwords, or sensitive credentials.
@MainActor
enum SettingsExportService {

    enum SettingsImportError: Error, LocalizedError {
        case invalidFormat
        case incompatibleVersion

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "Invalid settings file format."
            case .incompatibleVersion: return "Settings file version is not compatible."
            }
        }
    }

    // MARK: - Export

    static func exportSettings() -> Data? {
        var settings: [String: Any] = [:]

        // Metadata
        settings["exportVersion"] = 1
        settings["exportDate"] = ISO8601DateFormatter().string(from: Date())
        settings["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        // General — Age Indicators
        let syncStore = SyncedPreferencesStore.shared
        settings["lessonAgeWarningDays"] = syncStore.integer(forKey: "LessonAge.warningDays")
        settings["lessonAgeOverdueDays"] = syncStore.integer(forKey: "LessonAge.overdueDays")
        settings["lessonAgeFreshColorHex"] = syncStore.string(forKey: "LessonAge.freshColorHex")
        settings["lessonAgeWarningColorHex"] = syncStore.string(forKey: "LessonAge.warningColorHex")
        settings["lessonAgeOverdueColorHex"] = syncStore.string(forKey: "LessonAge.overdueColorHex")
        settings["workAgeWarningDays"] = syncStore.integer(forKey: "WorkAge.warningDays")
        settings["workAgeOverdueDays"] = syncStore.integer(forKey: "WorkAge.overdueDays")
        settings["workAgeFreshColorHex"] = syncStore.string(forKey: "WorkAge.freshColorHex")
        settings["workAgeWarningColorHex"] = syncStore.string(forKey: "WorkAge.warningColorHex")
        settings["workAgeOverdueColorHex"] = syncStore.string(forKey: "WorkAge.overdueColorHex")

        // AI Models (no API keys!)
        settings["aiModelChat"] = UserDefaults.standard.string(forKey: UserDefaultsKeys.aiModelChat)
        settings["aiModelLessonPlanning"] = UserDefaults.standard.string(
            forKey: UserDefaultsKeys.aiModelLessonPlanning
        )
        settings["aiModelBackgroundTasks"] = UserDefaults.standard.string(
            forKey: UserDefaultsKeys.aiModelBackgroundTasks
        )
        settings["ollamaBaseURL"] = UserDefaults.standard.string(forKey: UserDefaultsKeys.ollamaBaseURL)
        settings["ollamaModelName"] = UserDefaults.standard.string(forKey: UserDefaultsKeys.ollamaModelName)

        // Lesson Planning
        settings["lessonPlanningTimeout"] = UserDefaults.standard.integer(
            forKey: UserDefaultsKeys.lessonPlanningTimeout
        )
        settings["lessonPlanningDefaultDepth"] = UserDefaults.standard.string(
            forKey: UserDefaultsKeys.lessonPlanningDefaultDepth
        )
        settings["lessonPlanningTemperature"] = UserDefaults.standard.double(
            forKey: UserDefaultsKeys.lessonPlanningTemperature
        )

        // Backup
        settings["autoBackupEnabled"] = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoBackupEnabled)
        settings["autoBackupRetentionCount"] = UserDefaults.standard.integer(
            forKey: UserDefaultsKeys.autoBackupRetentionCount
        )
        settings["backupEncrypt"] = syncStore.bool(forKey: "Backup.encrypt")

        // Communication
        settings["attendanceEmailEnabled"] = syncStore.bool(forKey: "AttendanceEmail.enabled")
        settings["attendanceEmailTo"] = syncStore.string(forKey: "AttendanceEmail.to")
        settings["attendanceEmailFrom"] = syncStore.string(forKey: "AttendanceEmail.from")

        return try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Import

    static func importSettings(from data: Data) throws {
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsImportError.invalidFormat
        }

        guard let version = settings["exportVersion"] as? Int, version == 1 else {
            throw SettingsImportError.incompatibleVersion
        }

        let syncStore = SyncedPreferencesStore.shared
        let ud = UserDefaults.standard

        // General — Age Indicators
        if let v = settings["lessonAgeWarningDays"] as? Int { _ = syncStore.set(v, forKey: "LessonAge.warningDays") }
        if let v = settings["lessonAgeOverdueDays"] as? Int { _ = syncStore.set(v, forKey: "LessonAge.overdueDays") }
        if let v = settings["lessonAgeFreshColorHex"] as? String {
            _ = syncStore.set(v, forKey: "LessonAge.freshColorHex")
        }
        if let v = settings["lessonAgeWarningColorHex"] as? String {
            _ = syncStore.set(v, forKey: "LessonAge.warningColorHex")
        }
        if let v = settings["lessonAgeOverdueColorHex"] as? String {
            _ = syncStore.set(v, forKey: "LessonAge.overdueColorHex")
        }
        if let v = settings["workAgeWarningDays"] as? Int { _ = syncStore.set(v, forKey: "WorkAge.warningDays") }
        if let v = settings["workAgeOverdueDays"] as? Int { _ = syncStore.set(v, forKey: "WorkAge.overdueDays") }
        if let v = settings["workAgeFreshColorHex"] as? String {
            _ = syncStore.set(v, forKey: "WorkAge.freshColorHex")
        }
        if let v = settings["workAgeWarningColorHex"] as? String {
            _ = syncStore.set(v, forKey: "WorkAge.warningColorHex")
        }
        if let v = settings["workAgeOverdueColorHex"] as? String {
            _ = syncStore.set(v, forKey: "WorkAge.overdueColorHex")
        }

        // AI Models
        if let v = settings["aiModelChat"] as? String { ud.set(v, forKey: UserDefaultsKeys.aiModelChat) }
        if let v = settings["aiModelLessonPlanning"] as? String {
            ud.set(v, forKey: UserDefaultsKeys.aiModelLessonPlanning)
        }
        if let v = settings["aiModelBackgroundTasks"] as? String {
            ud.set(v, forKey: UserDefaultsKeys.aiModelBackgroundTasks)
        }
        if let v = settings["ollamaBaseURL"] as? String { ud.set(v, forKey: UserDefaultsKeys.ollamaBaseURL) }
        if let v = settings["ollamaModelName"] as? String { ud.set(v, forKey: UserDefaultsKeys.ollamaModelName) }

        // Lesson Planning
        if let v = settings["lessonPlanningTimeout"] as? Int {
            ud.set(v, forKey: UserDefaultsKeys.lessonPlanningTimeout)
        }
        if let v = settings["lessonPlanningDefaultDepth"] as? String {
            ud.set(v, forKey: UserDefaultsKeys.lessonPlanningDefaultDepth)
        }
        if let v = settings["lessonPlanningTemperature"] as? Double {
            ud.set(v, forKey: UserDefaultsKeys.lessonPlanningTemperature)
        }

        // Backup
        if let v = settings["autoBackupEnabled"] as? Bool { ud.set(v, forKey: UserDefaultsKeys.autoBackupEnabled) }
        if let v = settings["autoBackupRetentionCount"] as? Int {
            ud.set(v, forKey: UserDefaultsKeys.autoBackupRetentionCount)
        }
        if let v = settings["backupEncrypt"] as? Bool { _ = syncStore.set(v, forKey: "Backup.encrypt") }

        // Communication
        if let v = settings["attendanceEmailEnabled"] as? Bool {
            _ = syncStore.set(v, forKey: "AttendanceEmail.enabled")
        }
        if let v = settings["attendanceEmailTo"] as? String {
            _ = syncStore.set(v, forKey: "AttendanceEmail.to")
        }
        if let v = settings["attendanceEmailFrom"] as? String {
            _ = syncStore.set(v, forKey: "AttendanceEmail.from")
        }
    }
}
