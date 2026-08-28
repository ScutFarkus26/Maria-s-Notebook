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
        /// The value the app behaves with when the key was never customized.
        /// Exported in place of a missing key so importing a profile reproduces
        /// the exporting device's effective configuration — the stores' scalar
        /// getters would otherwise silently turn "never set" into 0/false.
        let defaultValue: Any
    }

    // Each setting is declared once — used for both export and import.
    private static let descriptors: [Descriptor] = [
        // General — Age Indicators (CDLesson)
        .init(jsonKey: "lessonAgeWarningDays", storeKey: "LessonAge.warningDays", store: .synced, type: .int,
              defaultValue: LessonAgeDefaults.warningDays),
        .init(jsonKey: "lessonAgeOverdueDays", storeKey: "LessonAge.overdueDays", store: .synced, type: .int,
              defaultValue: LessonAgeDefaults.overdueDays),
        .init(jsonKey: "lessonAgeFreshColorHex", storeKey: "LessonAge.freshColorHex", store: .synced, type: .string,
              defaultValue: LessonAgeDefaults.freshColorHex),
        .init(jsonKey: "lessonAgeWarningColorHex", storeKey: "LessonAge.warningColorHex",
              store: .synced, type: .string, defaultValue: LessonAgeDefaults.warningColorHex),
        .init(jsonKey: "lessonAgeOverdueColorHex", storeKey: "LessonAge.overdueColorHex",
              store: .synced, type: .string, defaultValue: LessonAgeDefaults.overdueColorHex),
        // General — Age Indicators (Work)
        .init(jsonKey: "workAgeWarningDays", storeKey: "WorkAge.warningDays", store: .synced, type: .int,
              defaultValue: WorkAgeDefaults.warningDays),
        .init(jsonKey: "workAgeOverdueDays", storeKey: "WorkAge.overdueDays", store: .synced, type: .int,
              defaultValue: WorkAgeDefaults.overdueDays),
        .init(jsonKey: "workAgeFreshColorHex", storeKey: "WorkAge.freshColorHex", store: .synced, type: .string,
              defaultValue: WorkAgeDefaults.freshColorHex),
        .init(jsonKey: "workAgeWarningColorHex", storeKey: "WorkAge.warningColorHex", store: .synced, type: .string,
              defaultValue: WorkAgeDefaults.warningColorHex),
        .init(jsonKey: "workAgeOverdueColorHex", storeKey: "WorkAge.overdueColorHex", store: .synced, type: .string,
              defaultValue: WorkAgeDefaults.overdueColorHex),
        // AI Models (no API keys!)
        .init(jsonKey: "aiModelChat", storeKey: UserDefaultsKeys.aiModelChat, store: .userDefaults, type: .string,
              defaultValue: AIFeatureArea.chat.defaultModel.rawValue),
        .init(jsonKey: "aiModelLessonPlanning", storeKey: UserDefaultsKeys.aiModelLessonPlanning,
              store: .userDefaults, type: .string,
              defaultValue: AIFeatureArea.lessonPlanning.defaultModel.rawValue),
        .init(jsonKey: "aiModelBackgroundTasks", storeKey: UserDefaultsKeys.aiModelBackgroundTasks,
              store: .userDefaults, type: .string,
              defaultValue: AIFeatureArea.backgroundTasks.defaultModel.rawValue),
        // CDLesson Planning — defaults mirror LessonPlanningSettingsView's @AppStorage values
        .init(jsonKey: "lessonPlanningTimeout", storeKey: UserDefaultsKeys.lessonPlanningTimeout,
              store: .userDefaults, type: .int, defaultValue: 120),
        .init(jsonKey: "lessonPlanningDefaultDepth", storeKey: UserDefaultsKeys.lessonPlanningDefaultDepth,
              store: .userDefaults, type: .string, defaultValue: "standard"),
        .init(jsonKey: "lessonPlanningTemperature", storeKey: UserDefaultsKeys.lessonPlanningTemperature,
              store: .userDefaults, type: .double, defaultValue: 0.3),
        // Backup — defaults mirror AutoBackupManager's @AppStorage values
        .init(jsonKey: "autoBackupEnabled", storeKey: UserDefaultsKeys.autoBackupEnabled,
              store: .userDefaults, type: .bool, defaultValue: true),
        .init(jsonKey: "autoBackupRetentionCount", storeKey: UserDefaultsKeys.autoBackupRetentionCount,
              store: .userDefaults, type: .int, defaultValue: 10),
        .init(jsonKey: "backupEncrypt", storeKey: "Backup.encrypt", store: .synced, type: .bool,
              defaultValue: false),
        // Communication — defaults mirror AttendanceEmail's @SyncedAppStorage values
        .init(jsonKey: "attendanceEmailEnabled", storeKey: "AttendanceEmail.enabled", store: .synced, type: .bool,
              defaultValue: true),
        .init(jsonKey: "attendanceEmailTo", storeKey: "AttendanceEmail.to", store: .synced, type: .string,
              defaultValue: ""),
        .init(jsonKey: "attendanceEmailFrom", storeKey: "AttendanceEmail.from", store: .synced, type: .string,
              defaultValue: ""),
        .init(jsonKey: "attendanceEmailNameOrder", storeKey: "AttendanceEmail.nameOrder", store: .synced,
              type: .string, defaultValue: AttendanceEmailNameOrder.firstLast.rawValue),
        .init(jsonKey: "attendanceEmailGroupByLevel", storeKey: "AttendanceEmail.groupByLevel", store: .synced,
              type: .bool, defaultValue: false)
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

    /// Reads the effective value for a setting: the raw stored object when the
    /// user customized it, otherwise the app default. Only object-level reads
    /// can distinguish "never set" (nil) from an explicit 0/false, per
    /// `UserDefaults.object(forKey:)` semantics.
    private static func readValue(
        _ desc: Descriptor, syncStore: SyncedPreferencesStore, userDefaults ud: UserDefaults
    ) -> Any {
        let stored: Any? = switch desc.store {
        case .synced: syncStore.get(key: desc.storeKey)
        case .userDefaults: ud.object(forKey: desc.storeKey)
        }
        switch desc.type {
        case .int:    return (stored as? Int) ?? desc.defaultValue
        case .string: return (stored as? String) ?? desc.defaultValue
        case .double: return (stored as? Double) ?? desc.defaultValue
        case .bool:   return (stored as? Bool) ?? desc.defaultValue
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
