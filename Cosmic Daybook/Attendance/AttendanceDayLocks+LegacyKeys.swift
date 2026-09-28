import Foundation
import CoreData
import OSLog

// The notebook's half of `AttendanceDayLocks`: carrying the old
// `Attendance.locked.<yyyy-MM-dd>` key-value locks into lock records. The
// Daybook Assistant never had those keys, so it doesn't compile this.

extension AttendanceDayLocks {

    // MARK: - The old key-value locks

    /// The days the old `Attendance.locked.<date>` settings lock.
    static func legacyLockedDays(in keys: [String: Any]) -> [Date] {
        keys.compactMap { key, value -> Date? in
            guard key.hasPrefix(legacyKeyPrefix), (value as? Bool) == true || (value as? NSNumber)?.boolValue == true
            else { return nil }
            let day = String(key.dropFirst(legacyKeyPrefix.count))
            return DateFormatters.isoDateLocal.date(from: day).map(AppCalendar.startOfDay)
        }
        .sorted()
    }

    /// Adds a lock row for every old-style locked day that has none.
    /// Idempotent; returns how many rows it added. The caller saves.
    @discardableResult
    static func migrateLegacyKeys(
        _ keys: [String: Any],
        role: CDClassroomMembership.ClassroomRole,
        in context: NSManagedObjectContext
    ) -> Int {
        guard role == .leadGuide else { return 0 }
        var added = 0
        for day in legacyLockedDays(in: keys) where !isLocked(day, in: context) {
            if setLocked(true, for: day, role: role, lockedByID: nil, in: context) { added += 1 }
        }
        if added > 0 {
            logger.notice("Carried \(added, privacy: .public) old-style attendance lock(s) into lock records")
        }
        return added
    }

    /// The old locks a restored backup's preferences carry.
    static func legacyLocks(in preferences: PreferencesDTO) -> [String: Any] {
        preferences.values.reduce(into: [String: Any]()) { result, entry in
            guard entry.key.hasPrefix(legacyKeyPrefix), case .bool(let locked) = entry.value else { return }
            result[entry.key] = locked
        }
    }

    /// Once per device and CloudKit environment, after the notebook has fully
    /// downloaded (so another device's lock records are already here): carries
    /// this device's old-style locks into lock records. The caller saves.
    @MainActor
    static func migrateStoredLegacyKeysIfNeeded(
        in context: NSManagedObjectContext,
        store: SyncedPreferencesStore = .shared,
        defaults: UserDefaults = .standard
    ) {
        let flag = UserDefaultsKeys.attendanceLocksCarriedOver
        guard !defaults.bool(forKey: flag), !FirstDownloadGate.isPending() else { return }
        let keys = store.storedKeys(withPrefix: legacyKeyPrefix)
        let values = Dictionary(uniqueKeysWithValues: keys.map { ($0, store.bool(forKey: $0) as Any) })
        migrateLegacyKeys(values, role: CDClassroomMembership.currentRole(in: context), in: context)
        defaults.set(true, forKey: flag)
    }
}
