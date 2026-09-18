import Foundation

/// Persists the lead guide's permission choices via iCloud KVS.
///
/// **Reach:** `NSUbiquitousKeyValueStore` syncs per Apple ID, so these choices
/// reach the lead guide's *own* devices only — an assistant on their own iCloud
/// account never sees them and falls back to `defaultEnabled`. Enforcing a
/// non-default matrix on the assistant's device requires moving this into a
/// shared-store entity (a future `ClassroomSettings`); until then the assistant
/// companion app hardcodes attendance-only writes anyway.
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

}
