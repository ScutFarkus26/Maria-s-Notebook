import Foundation
import Combine
import OSLog
import SwiftUI

/// Manages preferences that sync across devices via iCloud Key-Value Storage.
/// 
/// Best Practices:
/// - Use for user preferences that should sync (settings, colors, thresholds)
/// - KVS has a 1MB total limit across all keys
/// - Automatically falls back to UserDefaults if KVS is unavailable
/// - Handles migration from UserDefaults to KVS on first launch
@MainActor
public final class SyncedPreferencesStore: ObservableObject {
    public static let shared = SyncedPreferencesStore()
    
    private let kvStore = NSUbiquitousKeyValueStore.default
    private let userDefaults = UserDefaults.standard
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mariasnotebook", category: "SyncedPreferences")
    
    /// Keys that should sync across devices
    private static let syncedKeys: Set<String> = [
        // Attendance Email
        "AttendanceEmail.enabled",
        "AttendanceEmail.to",
        "AttendanceEmail.from",
        
        // Lesson Age Settings
        "LessonAge.warningDays",
        "LessonAge.overdueDays",
        "LessonAge.freshColorHex",
        "LessonAge.warningColorHex",
        "LessonAge.overdueColorHex",
        
        // Work Age Settings
        "WorkAge.warningDays",
        "WorkAge.overdueDays",
        "WorkAge.freshColorHex",
        "WorkAge.warningColorHex",
        "WorkAge.overdueColorHex",
        
        // Backup Settings
        "Backup.encrypt",
    ]
    
    private var changeObserver: NSObjectProtocol?
    
    private init() {
        // Migrate existing UserDefaults values to KVS on first launch
        migrateFromUserDefaultsIfNeeded()
        
        // Observe external changes (sync from other devices)
        observeExternalChanges()
        
        // Sync changes to KVS
        synchronize()
    }
    
    deinit {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Migration
    
    /// Migrates preferences from UserDefaults to KVS if not already migrated
    private func migrateFromUserDefaultsIfNeeded() {
        let migrationKey = "SyncedPreferencesMigrated"
        guard !userDefaults.bool(forKey: migrationKey) else {
            return // Already migrated
        }
        
        logger.info("Migrating preferences from UserDefaults to iCloud Key-Value Storage...")
        var migratedCount = 0
        
        for key in Self.syncedKeys {
            // Check if value exists in UserDefaults but not in KVS
            if let value = userDefaults.object(forKey: key), kvStore.object(forKey: key) == nil {
                kvStore.set(value, forKey: key)
                migratedCount += 1
                logger.debug("Migrated key: \(key)")
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
    
    // MARK: - External Change Observation
    
    /// Observes changes from other devices via NSUbiquitousKeyValueStoreDidChangeExternallyNotification
    private func observeExternalChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            if let userInfo = notification.userInfo,
               let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int {
                // NSUbiquitousKeyValueStoreChangeReasonKey values:
                // 0 = serverChange, 1 = initialSyncChange, 2 = quotaViolationChange, 3 = accountChange
                if reason == 0 { // serverChange - changes came from another device
                    if let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
                        self.logger.info("Received \(changedKeys.count) preference changes from iCloud")
                        // Post notification so views can update
                        NotificationCenter.default.post(
                            name: .syncedPreferencesDidChange,
                            object: self,
                            userInfo: ["changedKeys": changedKeys]
                        )
                    }
                }
                // Handle other cases (initialSyncChange, quotaViolationChange, accountChange) if needed
            }
        }
    }
    
    // MARK: - Public API
    
    /// Gets a value from synced storage (KVS) with fallback to UserDefaults
    public func get(key: String) -> Any? {
        if Self.syncedKeys.contains(key) {
            // Try KVS first
            if let value = kvStore.object(forKey: key) {
                return value
            }
            // Fallback to UserDefaults (for migration period)
            return userDefaults.object(forKey: key)
        } else {
            // Not a synced key, use UserDefaults
            return userDefaults.object(forKey: key)
        }
    }
    
    /// Sets a value in synced storage (KVS) for synced keys, UserDefaults otherwise
    @discardableResult
    public func set(_ value: Any?, forKey key: String) -> Bool {
        if Self.syncedKeys.contains(key) {
            // Store in KVS
            if let value = value {
                kvStore.set(value, forKey: key)
            } else {
                kvStore.removeObject(forKey: key)
            }
            let synced = synchronize()
            if !synced {
                logger.warning("Failed to sync preference '\(key)' to iCloud, storing in UserDefaults as fallback")
                // Fallback to UserDefaults if sync fails
                if let value = value {
                    userDefaults.set(value, forKey: key)
                } else {
                    userDefaults.removeObject(forKey: key)
                }
                return false
            }
            return true
        } else {
            // Not a synced key, use UserDefaults
            if let value = value {
                userDefaults.set(value, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
            return true
        }
    }
    
    /// Synchronizes KVS with iCloud
    @discardableResult
    public func synchronize() -> Bool {
        return kvStore.synchronize()
    }
    
    /// Removes a value from synced storage
    public func remove(key: String) {
        set(nil, forKey: key)
    }
    
    /// Checks if a key is configured to sync
    public func isSynced(key: String) -> Bool {
        return Self.syncedKeys.contains(key)
    }
    
    // MARK: - Type-Safe Convenience Methods
    
    public func bool(forKey key: String) -> Bool {
        if let value = get(key: key) as? Bool {
            return value
        }
        return false
    }
    
    public func integer(forKey key: String) -> Int {
        if let value = get(key: key) as? Int {
            return value
        }
        return 0
    }
    
    public func double(forKey key: String) -> Double {
        if let value = get(key: key) as? Double {
            return value
        }
        return 0.0
    }
    
    public func string(forKey key: String) -> String? {
        return get(key: key) as? String
    }
    
    public func set(_ value: Bool, forKey key: String) {
        set(value as Any?, forKey: key)
    }
    
    public func set(_ value: Int, forKey key: String) {
        set(value as Any?, forKey: key)
    }
    
    public func set(_ value: Double, forKey key: String) {
        set(value as Any?, forKey: key)
    }
    
    public func set(_ value: String?, forKey key: String) {
        set(value as Any?, forKey: key)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when synced preferences change from another device
    public static let syncedPreferencesDidChange = Notification.Name("syncedPreferencesDidChange")
}

// MARK: - Property Wrapper for SwiftUI

/// Property wrapper that automatically syncs preferences via iCloud Key-Value Storage
/// Usage: @SyncedAppStorage("key") var value: Type = defaultValue
@propertyWrapper
public struct SyncedAppStorage<T>: DynamicProperty {
    @ObservedObject private var store = SyncedPreferencesStore.shared
    private let key: String
    private let defaultValue: T
    
    public init(wrappedValue: T, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
    }
    
    public var wrappedValue: T {
        get {
            // Check if key exists first
            let existingValue = store.get(key: key)
            
            if T.self == Bool.self {
                if let boolValue = existingValue as? Bool {
                    return boolValue as! T
                }
                return defaultValue
            } else if T.self == Int.self {
                if let intValue = existingValue as? Int {
                    return intValue as! T
                }
                return defaultValue
            } else if T.self == Double.self {
                if let doubleValue = existingValue as? Double {
                    return doubleValue as! T
                }
                return defaultValue
            } else if T.self == String.self {
                if let stringValue = existingValue as? String {
                    return stringValue as! T
                }
                return defaultValue
            } else {
                if let value = existingValue as? T {
                    return value
                }
                return defaultValue
            }
        }
        nonmutating set {
            store.set(newValue as Any?, forKey: key)
            // Trigger update notification
            store.objectWillChange.send()
        }
    }
    
    public var projectedValue: Binding<T> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }
}

