//
//  APIKeyStore.swift
//  Cosmic Daybook
//
//  One Keychain-backed store for provider API keys. `AnthropicAPIClient` and
//  `OpenAIAPIClient` each forward their key helpers here, so "Keychain first,
//  then migrate the legacy plaintext UserDefaults value once" lives in a
//  single place instead of once per provider.
//

import Foundation
import OSLog
import Security

/// Secret storage behind an `APIKeyStore`. `KeychainStore` is the only
/// production implementation; tests substitute an in-memory double so they
/// never touch the real Keychain.
protocol APIKeySecretStore {
    func get() throws -> Data?
    func set(_ data: Data, accessibility: CFString) throws
    func delete() throws
}

extension KeychainStore: APIKeySecretStore {}

/// Loads, saves, validates and clears one provider's API key.
///
/// Reads the Keychain first. A key still sitting in the provider's legacy
/// plaintext UserDefaults entry is copied into the Keychain, removed from
/// UserDefaults and logged once — exactly what each client used to do itself.
struct APIKeyStore {
    /// Key prefixes this provider issues; `hasKey()` accepts a key only when
    /// it starts with one of them.
    let acceptedPrefixes: [String]
    /// The plaintext UserDefaults entry this provider used before the Keychain.
    let legacyDefaultsKey: String

    private let secrets: APIKeySecretStore
    private let defaults: UserDefaults
    private let logger: Logger
    private let migrationLogMessage: String
    private let saveFailureLogMessage: String

    init(
        secrets: APIKeySecretStore,
        legacyDefaultsKey: String,
        acceptedPrefixes: [String],
        logger: Logger,
        migrationLogMessage: String,
        saveFailureLogMessage: String,
        defaults: UserDefaults = .standard
    ) {
        self.secrets = secrets
        self.legacyDefaultsKey = legacyDefaultsKey
        self.acceptedPrefixes = acceptedPrefixes
        self.logger = logger
        self.migrationLogMessage = migrationLogMessage
        self.saveFailureLogMessage = saveFailureLogMessage
        self.defaults = defaults
    }

    /// The stored key, or an empty string when none is configured.
    func load() -> String {
        // Try the Keychain first (secure storage).
        if let data = try? secrets.get(), let key = String(data: data, encoding: .utf8), !key.isEmpty {
            return key
        }

        // Fall back to UserDefaults and auto-migrate to the Keychain.
        if let key = defaults.string(forKey: legacyDefaultsKey), !key.isEmpty {
            if let data = key.data(using: .utf8) {
                try? secrets.set(data, accessibility: kSecAttrAccessibleAfterFirstUnlock)
                defaults.removeObject(forKey: legacyDefaultsKey)
                logger.info("\(migrationLogMessage, privacy: .public)")
            }
            return key
        }

        return ""
    }

    /// Writes the key to the Keychain.
    func save(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }
        do {
            try secrets.set(data, accessibility: kSecAttrAccessibleAfterFirstUnlock)
        } catch {
            logger.error("\(saveFailureLogMessage, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Whether a non-empty, plausibly-shaped key is configured.
    func hasKey() -> Bool {
        let key = load()
        return !key.isEmpty && acceptedPrefixes.contains(where: key.hasPrefix)
    }

    /// Removes the key from the Keychain and from the legacy UserDefaults entry.
    func clear() {
        try? secrets.delete()
        defaults.removeObject(forKey: legacyDefaultsKey)
    }
}

// MARK: - Providers

extension APIKeyStore {

    /// Anthropic key. The Keychain service/account are unchanged from when this
    /// lived in `AnthropicAPIClient`, so existing keys are still found.
    static let anthropic = APIKeyStore(
        secrets: KeychainStore(
            service: "com.danielsdeberry.MariasNoteBook",
            account: "anthropicAPIKey"
        ),
        legacyDefaultsKey: UserDefaultsKeys.anthropicAPIKey,
        acceptedPrefixes: ["sk-ant-api03-", "sk-ant-"],
        logger: .ai,
        migrationLogMessage: "Migrated API key from UserDefaults to Keychain",
        saveFailureLogMessage: "Failed to save API key to Keychain"
    )

    /// OpenAI key. Keychain service/account unchanged from `OpenAIAPIClient`.
    static let openAI = APIKeyStore(
        secrets: KeychainStore(
            service: "com.danielsdeberry.MariasNoteBook",
            account: "openAIAPIKey"
        ),
        legacyDefaultsKey: UserDefaultsKeys.openAIAPIKey,
        acceptedPrefixes: ["sk-"],
        logger: .ai,
        migrationLogMessage: "Migrated OpenAI key from UserDefaults to Keychain",
        saveFailureLogMessage: "Failed to save OpenAI API key"
    )
}
