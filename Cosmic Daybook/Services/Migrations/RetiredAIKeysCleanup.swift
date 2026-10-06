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

    /// The Keychain's answers that mean it won't let this device remove the
    /// items: locked (interaction not allowed) or not ours to touch (auth
    /// failed). After `maxRefusals` launches that end in one, the cleanup
    /// counts as done: an item nobody reads isn't worth asking for, on every
    /// launch, for good.
    static let refusals: Set<OSStatus> = [errSecInteractionNotAllowed, errSecAuthFailed]
    static let maxRefusals = 3

    /// Deletes both Keychain items and the UserDefaults entries once. A
    /// Keychain failure (for example, still locked before first unlock) leaves
    /// the flag unset, so the next launch tries again; the third launch the
    /// Keychain refuses counts it done. Returns whether this call finished the
    /// cleanup.
    @discardableResult
    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        deleteKeychainItem: (_ service: String, _ account: String) -> OSStatus = deleteGenericPassword
    ) -> Bool {
        guard !defaults.bool(forKey: UserDefaultsKeys.retiredAIKeysRemovedV1) else { return false }
        var finished = true
        var refused = false
        for account in keychainAccounts {
            let status = deleteKeychainItem(keychainService, account)
            guard status != errSecSuccess, status != errSecItemNotFound else { continue }
            finished = false
            refused = refused || refusals.contains(status)
            logger.warning(
                "Retired API key \(account, privacy: .public) not removed (OSStatus \(status, privacy: .public))"
            )
        }
        for key in defaultsKeys {
            defaults.removeObject(forKey: key)
        }
        if !finished {
            guard refused else { return false }
            let count = defaults.integer(forKey: UserDefaultsKeys.retiredAIKeysRefusals) + 1
            guard count >= maxRefusals else {
                defaults.set(count, forKey: UserDefaultsKeys.retiredAIKeysRefusals)
                return false
            }
            logger.notice("Retired API keys: the Keychain refused \(count, privacy: .public) launches; leaving them")
        }
        defaults.set(true, forKey: UserDefaultsKeys.retiredAIKeysRemovedV1)
        defaults.removeObject(forKey: UserDefaultsKeys.retiredAIKeysRefusals)
        if finished {
            logger.notice("Removed the retired Claude and OpenAI keys and model choices")
        }
        return true
    }

    /// The launch's call: `SecItemDelete` can wait on the Keychain (before
    /// first unlock it does), so it runs off the main thread. `defaultsSuite`
    /// names the defaults to use; nil is the app's own.
    @concurrent
    @discardableResult
    static func runOffMainThread(
        defaultsSuite: String? = nil,
        deleteKeychainItem: @Sendable (_ service: String, _ account: String) -> OSStatus = deleteGenericPassword
    ) async -> Bool {
        let defaults = defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        return runIfNeeded(defaults: defaults, deleteKeychainItem: deleteKeychainItem)
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
