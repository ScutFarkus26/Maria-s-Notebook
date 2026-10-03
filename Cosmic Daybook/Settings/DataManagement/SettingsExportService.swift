import Foundation

// MARK: - Settings Export Service

/// Sync and backup › Move settings to another device: writes the guide's
/// settings to a small JSON file and reads one back on another device.
///
/// The settings are the ones every backup carries
/// (`BackupPreferencesService.preferenceKeys`), less the few that describe
/// this device rather than the guide's choices. That list already leaves out
/// device plumbing (sync tokens, window positions, the Claude connection), and
/// an imported file can only set keys on it.
enum SettingsExportService {

    enum SettingsImportError: Error, LocalizedError {
        case invalidFormat
        case incompatibleVersion

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "This file isn't a Cosmic Daybook settings file."
            case .incompatibleVersion:
                return "This settings file came from a newer version of Cosmic Daybook. " +
                    "Update the app on this device, then import it again."
            }
        }
    }

    /// The file version this build writes. Version 1 (until 2026-09-30) held
    /// 21 hand-picked settings under names of its own; it still imports.
    static let currentVersion = 2

    // MARK: - Keys

    /// Backed-up keys that stay behind when settings move to another device.
    private static let deviceOnlyKeys: Set<String> = [
        // When this device last backed up. Copied across, it would hide the
        // other device's "no backup yet" warning.
        "LastBackupTimeInterval",
        UserDefaultsKeys.lastBackupTimeInterval,
        // Album folders and files on this device; they mean nothing elsewhere.
        UserDefaultsKeys.albumsFolderBookmarks,
        UserDefaultsKeys.albumsFingerprints,
        UserDefaultsKeys.albumsLastSeenModDates
    ]

    /// Every setting the file carries. The per-date attendance locks
    /// (`BackupPreferencesService.preferenceKeyPrefixes`) are classroom
    /// records, not settings, so they stay out.
    static let transferKeys: [String] =
        BackupPreferencesService.preferenceKeys.filter { !deviceOnlyKeys.contains($0) }

    // MARK: - File Format

    /// Version 2: each setting under its stored key, typed as in a backup's
    /// `preferences.json`.
    private nonisolated struct Profile: Codable {
        var exportVersion: Int
        var exportDate: String
        var appVersion: String
        /// The settings the exporting device has chosen. One it never changed
        /// isn't in the file, and importing leaves the other device's own choice
        /// alone: clearing it would reach every device through iCloud.
        var settings: [String: PreferenceValueDTO]
    }

    // MARK: - Export

    /// - Parameters:
    ///   - defaults: Where settings that don't sync through iCloud live.
    ///   - syncedStore: Where synced settings live; nil reads every key from `defaults` (tests).
    static func exportSettings(
        defaults: UserDefaults = .standard,
        syncedStore: SyncedPreferencesStore? = .shared
    ) -> Data? {
        let storage = Storage(defaults: defaults, syncedStore: syncedStore)
        var settings: [String: PreferenceValueDTO] = [:]
        for key in transferKeys {
            guard let stored = storage.value(forKey: key) else { continue }
            if let value = BackupPreferencesService.dtoValue(for: stored) {
                settings[key] = value
            }
        }

        let profile = Profile(
            exportVersion: currentVersion,
            exportDate: DateFormatters.iso8601DateTime.string(from: Date()),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            settings: settings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(profile)
    }

    // MARK: - Import

    static func importSettings(
        from data: Data,
        defaults: UserDefaults = .standard,
        syncedStore: SyncedPreferencesStore? = .shared
    ) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsImportError.invalidFormat
        }
        let storage = Storage(defaults: defaults, syncedStore: syncedStore)

        switch object["exportVersion"] as? Int {
        case .some(1):
            importVersion1(object, into: storage)
        case .some(currentVersion):
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let profile = try? decoder.decode(Profile.self, from: data) else {
                throw SettingsImportError.invalidFormat
            }
            let known = Set(transferKeys)
            for (key, value) in profile.settings where known.contains(key) {
                if let native = BackupPreferencesService.nativeValue(for: value) {
                    storage.set(native, forKey: key)
                }
            }
        case .some:
            throw SettingsImportError.incompatibleVersion
        case .none:
            throw SettingsImportError.invalidFormat
        }
    }

    // MARK: - Version 1

    private enum ValueType { case int, string, double, bool }

    private struct Version1Key {
        let jsonKey: String
        let storeKey: String
        let type: ValueType

        init(_ jsonKey: String, _ storeKey: String, _ type: ValueType) {
            self.jsonKey = jsonKey
            self.storeKey = storeKey
            self.type = type
        }
    }

    /// Version 1's names for its settings. It wrote every one, with the app
    /// default in place of a value never set, so importing it sets them all.
    /// Its `backupEncrypt` is skipped: nothing reads it.
    private static let version1Keys: [Version1Key] = [
        .init("lessonAgeWarningDays", "LessonAge.warningDays", .int),
        .init("lessonAgeOverdueDays", "LessonAge.overdueDays", .int),
        .init("lessonAgeFreshColorHex", "LessonAge.freshColorHex", .string),
        .init("lessonAgeWarningColorHex", "LessonAge.warningColorHex", .string),
        .init("lessonAgeOverdueColorHex", "LessonAge.overdueColorHex", .string),
        .init("workAgeWarningDays", "WorkAge.warningDays", .int),
        .init("workAgeOverdueDays", "WorkAge.overdueDays", .int),
        .init("workAgeFreshColorHex", "WorkAge.freshColorHex", .string),
        .init("workAgeWarningColorHex", "WorkAge.warningColorHex", .string),
        .init("workAgeOverdueColorHex", "WorkAge.overdueColorHex", .string),
        .init("lessonPlanningTimeout", UserDefaultsKeys.lessonPlanningTimeout, .int),
        .init("lessonPlanningDefaultDepth", UserDefaultsKeys.lessonPlanningDefaultDepth, .string),
        .init("lessonPlanningTemperature", UserDefaultsKeys.lessonPlanningTemperature, .double),
        .init("autoBackupEnabled", UserDefaultsKeys.autoBackupEnabled, .bool),
        .init("autoBackupRetentionCount", UserDefaultsKeys.autoBackupRetentionCount, .int),
        .init("attendanceEmailEnabled", "AttendanceEmail.enabled", .bool),
        .init("attendanceEmailTo", "AttendanceEmail.to", .string),
        .init("attendanceEmailFrom", "AttendanceEmail.from", .string),
        .init("attendanceEmailNameOrder", "AttendanceEmail.nameOrder", .string),
        .init("attendanceEmailGroupByLevel", "AttendanceEmail.groupByLevel", .bool)
    ]

    private static func importVersion1(_ settings: [String: Any], into storage: Storage) {
        for entry in version1Keys {
            guard let value = settings[entry.jsonKey] else { continue }
            let typed: Any? = switch entry.type {
            case .int: value as? Int
            case .string: value as? String
            case .double: value as? Double
            case .bool: value as? Bool
            }
            if let typed {
                storage.set(typed, forKey: entry.storeKey)
            }
        }
    }

    // MARK: - Storage

    /// Routes each key to where the app keeps it: synced settings in iCloud
    /// (`SyncedPreferencesStore`), the rest in `defaults`.
    private struct Storage {
        let defaults: UserDefaults
        let syncedStore: SyncedPreferencesStore?

        func value(forKey key: String) -> Any? {
            if let syncedStore, syncedStore.isSynced(key: key) {
                return syncedStore.get(key: key)
            }
            return defaults.object(forKey: key)
        }

        func set(_ value: Any?, forKey key: String) {
            if let syncedStore, syncedStore.isSynced(key: key) {
                syncedStore.set(value, forKey: key)
            } else if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
