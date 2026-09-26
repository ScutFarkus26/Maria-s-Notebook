import Foundation
import OSLog
import Security

/// One-time, per-device removal of what the retired Claude and OpenAI
/// integrations left behind when the app's own AI became Apple-only
/// (8c438851): the two API keys in the Keychain, their older plaintext copies
/// in UserDefaults, and the per-feature model choices. Nothing reads any of it.
nonisolated enum RetiredAIKeysCleanup {
    private static let logger = Logger.migration

    /// Where `APIKeyStore` kept the keys. Neither item was synchronizable, so
    /// each device holds its own copy and runs this itself.
    static let keychainService = "com.danielsdeberry.MariasNoteBook"
    static let keychainAccounts = ["anthropicAPIKey", "openAIAPIKey"]

    /// The legacy plaintext keys and the removed model choices.
    static let defaultsKeys = [
        "anthropicAPIKey", "openAIAPIKey",
        "AI.chatModel", "AI.lessonPlanningModel", "AI.backgroundTasksModel", "LessonPlanning.model"
    ]

    /// Deletes both Keychain items and the UserDefaults entries once. A
    /// Keychain failure (for example, still locked before first unlock) leaves
    /// the flag unset, so the next launch tries again. Returns whether this
    /// call finished the cleanup.
    @discardableResult
    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        deleteKeychainItem: (_ service: String, _ account: String) -> OSStatus = deleteGenericPassword
    ) -> Bool {
        guard !defaults.bool(forKey: UserDefaultsKeys.retiredAIKeysRemovedV1) else { return false }
        var finished = true
        for account in keychainAccounts {
            let status = deleteKeychainItem(keychainService, account)
            guard status != errSecSuccess, status != errSecItemNotFound else { continue }
            finished = false
            logger.warning(
                "Retired API key \(account, privacy: .public) not removed (OSStatus \(status, privacy: .public))"
            )
        }
        for key in defaultsKeys {
            defaults.removeObject(forKey: key)
        }
        guard finished else { return false }
        defaults.set(true, forKey: UserDefaultsKeys.retiredAIKeysRemovedV1)
        logger.notice("Removed the retired Claude and OpenAI keys and model choices")
        return true
    }

    static func deleteGenericPassword(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary)
    }
}
