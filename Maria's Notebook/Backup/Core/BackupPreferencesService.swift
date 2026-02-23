import Foundation

// MARK: - Backup Preferences Service

/// Service responsible for exporting and importing user preferences in backups.
enum BackupPreferencesService {

    // MARK: - Preference Keys

    /// Keys for preferences that are included in backups.
    static let preferenceKeys: [String] = [
        "AttendanceEmail.enabled",
        "AttendanceEmail.to",
        "LessonAge.warningDays",
        "LessonAge.overdueDays",
        "WorkAge.warningDays",
        "WorkAge.overdueDays",
        "LessonAge.freshColorHex",
        "LessonAge.warningColorHex",
        "LessonAge.overdueColorHex",
        "WorkAge.freshColorHex",
        "WorkAge.warningColorHex",
        "WorkAge.overdueColorHex",
        "Backup.encrypt",
        "LastBackupTimeInterval",
        "lastBackupTimeInterval"
    ]

    // MARK: - Export

    /// Builds a PreferencesDTO from current user preferences.
    static func buildPreferencesDTO() -> PreferencesDTO {
        let syncedStore = SyncedPreferencesStore.shared
        let defaults = UserDefaults.standard
        var map: [String: PreferenceValueDTO] = [:]

        for key in preferenceKeys {
            let obj: Any?
            if syncedStore.isSynced(key: key) {
                obj = syncedStore.get(key: key)
            } else {
                obj = defaults.object(forKey: key)
            }

            if let obj = obj {
                switch obj {
                case let b as Bool:
                    map[key] = .bool(b)
                case let i as Int:
                    map[key] = .int(i)
                case let d as Double:
                    map[key] = .double(d)
                case let s as String:
                    map[key] = .string(s)
                case let data as Data:
                    map[key] = .data(data)
                case let date as Date:
                    map[key] = .date(date)
                default:
                    map[key] = .string(String(describing: obj))
                }
            }
        }

        return PreferencesDTO(values: map)
    }

    // MARK: - Import

    /// Applies a PreferencesDTO to user preferences.
    static func applyPreferencesDTO(_ dto: PreferencesDTO) {
        let syncedStore = SyncedPreferencesStore.shared
        let defaults = UserDefaults.standard

        for (key, value) in dto.values {
            if syncedStore.isSynced(key: key) {
                switch value {
                case .bool(let b):
                    syncedStore.set(b, forKey: key)
                case .int(let i):
                    syncedStore.set(i, forKey: key)
                case .double(let d):
                    syncedStore.set(d, forKey: key)
                case .string(let s):
                    syncedStore.set(s, forKey: key)
                case .data(let data):
                    syncedStore.set(data as Any?, forKey: key)
                case .date(let date):
                    syncedStore.set(date.timeIntervalSinceReferenceDate, forKey: key)
                }
            } else {
                switch value {
                case .bool(let b):
                    defaults.set(b, forKey: key)
                case .int(let i):
                    defaults.set(i, forKey: key)
                case .double(let d):
                    defaults.set(d, forKey: key)
                case .string(let s):
                    defaults.set(s, forKey: key)
                case .data(let data):
                    defaults.set(data, forKey: key)
                case .date(let date):
                    defaults.set(date, forKey: key)
                }
            }
        }
    }
}
