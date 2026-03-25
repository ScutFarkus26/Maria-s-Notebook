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

    // MARK: - Setting Descriptors

    private enum Store { case synced, userDefaults }
    private enum ValueType { case int, string, double, bool }

    private struct Descriptor {
        let jsonKey: String
        let storeKey: String
        let store: Store
        let type: ValueType
    }

    // Each setting is declared once — used for both export and import.
    private static let descriptors: [Descriptor] = [
        // General — Age Indicators (Lesson)
        .init(jsonKey: "lessonAgeWarningDays", storeKey: "LessonAge.warningDays", store: .synced, type: .int),
        .init(jsonKey: "lessonAgeOverdueDays", storeKey: "LessonAge.overdueDays", store: .synced, type: .int),
        .init(jsonKey: "lessonAgeFreshColorHex", storeKey: "LessonAge.freshColorHex", store: .synced, type: .string),
        .init(jsonKey: "lessonAgeWarningColorHex", storeKey: "LessonAge.warningColorHex",
              store: .synced, type: .string),
        .init(jsonKey: "lessonAgeOverdueColorHex", storeKey: "LessonAge.overdueColorHex",
              store: .synced, type: .string),
        // General — Age Indicators (Work)
        .init(jsonKey: "workAgeWarningDays", storeKey: "WorkAge.warningDays", store: .synced, type: .int),
        .init(jsonKey: "workAgeOverdueDays", storeKey: "WorkAge.overdueDays", store: .synced, type: .int),
        .init(jsonKey: "workAgeFreshColorHex", storeKey: "WorkAge.freshColorHex", store: .synced, type: .string),
        .init(jsonKey: "workAgeWarningColorHex", storeKey: "WorkAge.warningColorHex", store: .synced, type: .string),
        .init(jsonKey: "workAgeOverdueColorHex", storeKey: "WorkAge.overdueColorHex", store: .synced, type: .string),
        // AI Models (no API keys!)
        .init(jsonKey: "aiModelChat", storeKey: UserDefaultsKeys.aiModelChat, store: .userDefaults, type: .string),
        .init(jsonKey: "aiModelLessonPlanning", storeKey: UserDefaultsKeys.aiModelLessonPlanning,
              store: .userDefaults, type: .string),
        .init(jsonKey: "aiModelBackgroundTasks", storeKey: UserDefaultsKeys.aiModelBackgroundTasks,
              store: .userDefaults, type: .string),
        .init(jsonKey: "ollamaBaseURL", storeKey: UserDefaultsKeys.ollamaBaseURL,
              store: .userDefaults, type: .string),
        .init(jsonKey: "ollamaModelName", storeKey: UserDefaultsKeys.ollamaModelName,
              store: .userDefaults, type: .string),
        // Lesson Planning
        .init(jsonKey: "lessonPlanningTimeout", storeKey: UserDefaultsKeys.lessonPlanningTimeout,
              store: .userDefaults, type: .int),
        .init(jsonKey: "lessonPlanningDefaultDepth", storeKey: UserDefaultsKeys.lessonPlanningDefaultDepth,
              store: .userDefaults, type: .string),
        .init(jsonKey: "lessonPlanningTemperature", storeKey: UserDefaultsKeys.lessonPlanningTemperature,
              store: .userDefaults, type: .double),
        // Backup
        .init(jsonKey: "autoBackupEnabled", storeKey: UserDefaultsKeys.autoBackupEnabled,
              store: .userDefaults, type: .bool),
        .init(jsonKey: "autoBackupRetentionCount", storeKey: UserDefaultsKeys.autoBackupRetentionCount,
              store: .userDefaults, type: .int),
        .init(jsonKey: "backupEncrypt", storeKey: "Backup.encrypt", store: .synced, type: .bool),
        // Communication
        .init(jsonKey: "attendanceEmailEnabled", storeKey: "AttendanceEmail.enabled", store: .synced, type: .bool),
        .init(jsonKey: "attendanceEmailTo", storeKey: "AttendanceEmail.to", store: .synced, type: .string),
        .init(jsonKey: "attendanceEmailFrom", storeKey: "AttendanceEmail.from", store: .synced, type: .string)
    ]

    // MARK: - Export

    static func exportSettings() -> Data? {
        var settings: [String: Any] = [:]

        // Metadata
        settings["exportVersion"] = 1
        settings["exportDate"] = DateFormatters.iso8601DateTime.string(from: Date())
        settings["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let syncStore = SyncedPreferencesStore.shared
        let ud = UserDefaults.standard

        for desc in descriptors {
            settings[desc.jsonKey] = readValue(desc, syncStore: syncStore, userDefaults: ud)
        }

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

        for desc in descriptors {
            guard let value = settings[desc.jsonKey] else { continue }
            writeValue(desc, value: value, syncStore: syncStore, userDefaults: ud)
        }
    }

    // MARK: - Read/Write Helpers

    private static func readValue(
        _ desc: Descriptor, syncStore: SyncedPreferencesStore, userDefaults ud: UserDefaults
    ) -> Any {
        switch (desc.store, desc.type) {
        case (.synced, .int):         return syncStore.integer(forKey: desc.storeKey)
        case (.synced, .string):      return syncStore.string(forKey: desc.storeKey) as Any
        case (.synced, .double):      return syncStore.double(forKey: desc.storeKey)
        case (.synced, .bool):        return syncStore.bool(forKey: desc.storeKey)
        case (.userDefaults, .int):    return ud.integer(forKey: desc.storeKey)
        case (.userDefaults, .string): return ud.string(forKey: desc.storeKey) as Any
        case (.userDefaults, .double): return ud.double(forKey: desc.storeKey)
        case (.userDefaults, .bool):   return ud.bool(forKey: desc.storeKey)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func writeValue(
        _ desc: Descriptor, value: Any, syncStore: SyncedPreferencesStore, userDefaults ud: UserDefaults
    ) {
        switch (desc.store, desc.type) {
        case (.synced, .int):         if let v = value as? Int { syncStore.set(v, forKey: desc.storeKey) }
        case (.synced, .string):      if let v = value as? String { syncStore.set(v, forKey: desc.storeKey) }
        case (.synced, .double):      if let v = value as? Double { syncStore.set(v, forKey: desc.storeKey) }
        case (.synced, .bool):        if let v = value as? Bool { syncStore.set(v, forKey: desc.storeKey) }
        case (.userDefaults, .int):    if let v = value as? Int { ud.set(v, forKey: desc.storeKey) }
        case (.userDefaults, .string): if let v = value as? String { ud.set(v, forKey: desc.storeKey) }
        case (.userDefaults, .double): if let v = value as? Double { ud.set(v, forKey: desc.storeKey) }
        case (.userDefaults, .bool):   if let v = value as? Bool { ud.set(v, forKey: desc.storeKey) }
        }
    }
}
