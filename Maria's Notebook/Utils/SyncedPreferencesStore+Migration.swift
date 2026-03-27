import Foundation
import OSLog

// MARK: - Migration from UserDefaults to iCloud KVS

extension SyncedPreferencesStore {
    /// Migrates preferences from UserDefaults to KVS if not already migrated
    func migrateFromUserDefaultsIfNeeded() {
        let migrationKey = "SyncedPreferencesMigrated"
        guard !userDefaults.bool(forKey: migrationKey) else {
            return // Already migrated
        }

        logger.info("Migrating preferences from UserDefaults to iCloud Key-Value Storage...")
        var migratedCount = 0

        // Migrate exact keys
        for key in Self.syncedKeys where migrateKeyIfNeeded(key) {
            migratedCount += 1
        }

        // Migrate prefix-based keys (e.g., attendance lock keys)
        let allUserDefaultsKeys = userDefaults.dictionaryRepresentation().keys
        for key in allUserDefaultsKeys where Self.syncedKeyPrefixes.contains(where: { key.hasPrefix($0) }) {
            if migrateKeyIfNeeded(key) {
                migratedCount += 1
            }
        }

        if migratedCount > 0 {
            let synced = kvStore.synchronize()
            if synced {
                logger.info("Successfully migrated \(migratedCount) preferences to iCloud Key-Value Storage")
            } else {
                logger.error("Failed to sync migrated preferences to iCloud")
            }
        }

        userDefaults.set(true, forKey: migrationKey)
    }

    /// Migrates a single key from UserDefaults to KVS if it exists locally but not in KVS.
    /// Returns `true` if the key was migrated.
    private func migrateKeyIfNeeded(_ key: String) -> Bool {
        if let value = userDefaults.object(forKey: key), kvStore.object(forKey: key) == nil {
            kvStore.set(value, forKey: key)
            logger.debug("Migrated key: \(key)")
            return true
        }
        return false
    }
}
