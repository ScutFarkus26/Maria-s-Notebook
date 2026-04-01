import Foundation

/// Persists the lead guide's permission choices via CloudKit KVS.
/// Both lead guide and assistant see the same config via NSUbiquitousKeyValueStore.
enum SharingPreferences {
    private static let kvsKey = "assistantWritableCategories"

    /// Returns the set of categories assistants are allowed to write.
    static func assistantWritableCategories() -> Set<SharingPermissionCategory> {
        if let stored = NSUbiquitousKeyValueStore.default.array(forKey: kvsKey) as? [String] {
            let categories = stored.compactMap { SharingPermissionCategory(rawValue: $0) }
            return Set(categories)
        }
        // Also check UserDefaults as fallback (offline or KVS not yet synced)
        if let stored = UserDefaults.standard.array(forKey: kvsKey) as? [String] {
            let categories = stored.compactMap { SharingPermissionCategory(rawValue: $0) }
            return Set(categories)
        }
        return SharingPermissionCategory.defaultEnabled
    }

    /// Sets the categories assistants are allowed to write.
    static func setAssistantWritableCategories(_ categories: Set<SharingPermissionCategory>) {
        let rawValues = categories.map(\.rawValue)
        NSUbiquitousKeyValueStore.default.set(rawValues, forKey: kvsKey)
        UserDefaults.standard.set(rawValues, forKey: kvsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Whether a specific category is enabled for assistants.
    static func isCategoryEnabled(_ category: SharingPermissionCategory) -> Bool {
        assistantWritableCategories().contains(category)
    }

    /// Toggle a specific category for assistants.
    static func toggleCategory(_ category: SharingPermissionCategory) {
        var current = assistantWritableCategories()
        if current.contains(category) {
            current.remove(category)
        } else {
            current.insert(category)
        }
        setAssistantWritableCategories(current)
    }
}
