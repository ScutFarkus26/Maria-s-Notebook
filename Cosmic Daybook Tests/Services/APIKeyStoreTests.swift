//
//  APIKeyStoreTests.swift
//  Cosmic Daybook Tests
//
//  APIKeyStore backs both provider clients' key helpers. Every test here runs
//  against an in-memory secret store and a scratch UserDefaults suite, so the
//  real Keychain and the app's own defaults are never touched.
//

import Foundation
import OSLog
import Security
import Testing
@testable import CosmicDaybook

/// Stand-in for `KeychainStore`.
private final class InMemorySecretStore: APIKeySecretStore {
    private(set) var stored: Data?
    private(set) var writeCount = 0
    private(set) var deleteCount = 0

    init(value: String? = nil) {
        stored = value.map { Data($0.utf8) }
    }

    var value: String? {
        stored.flatMap { String(data: $0, encoding: .utf8) }
    }

    func get() throws -> Data? { stored }

    func set(_ data: Data, accessibility: CFString) throws {
        stored = data
        writeCount += 1
    }

    func delete() throws {
        stored = nil
        deleteCount += 1
    }
}

@Suite("API Key Store")
@MainActor
struct APIKeyStoreTests {

    private static let legacyDefaultsKey = "APIKeyStoreTests.legacyAPIKey"
    private static let anthropicPrefixes = ["sk-ant-api03-", "sk-ant-"]
    private static let openAIPrefixes = ["sk-"]

    // MARK: - Helpers

    private func makeStore(
        secrets: APIKeySecretStore,
        defaults: UserDefaults,
        prefixes: [String] = APIKeyStoreTests.anthropicPrefixes
    ) -> APIKeyStore {
        APIKeyStore(
            secrets: secrets,
            legacyDefaultsKey: Self.legacyDefaultsKey,
            acceptedPrefixes: prefixes,
            logger: .ai,
            migrationLogMessage: "Migrated test key from UserDefaults to Keychain",
            saveFailureLogMessage: "Failed to save test key",
            defaults: defaults
        )
    }

    /// Runs `body` with a throwaway defaults suite that is removed afterwards.
    private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "APIKeyStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    // MARK: - Loading

    @Test("A Keychain key wins over the legacy plaintext default")
    func keychainValueBeatsLegacyDefault() throws {
        try withScratchDefaults { defaults in
            let secrets = InMemorySecretStore(value: "sk-ant-from-keychain")
            defaults.set("sk-ant-from-defaults", forKey: Self.legacyDefaultsKey)
            let store = makeStore(secrets: secrets, defaults: defaults)

            #expect(store.load() == "sk-ant-from-keychain")
            // The legacy entry is left alone; only a Keychain miss migrates it.
            #expect(defaults.string(forKey: Self.legacyDefaultsKey) == "sk-ant-from-defaults")
            #expect(secrets.writeCount == 0)
        }
    }

    @Test("A legacy plaintext key migrates into the Keychain exactly once")
    func legacyDefaultMigratesOnce() throws {
        try withScratchDefaults { defaults in
            let secrets = InMemorySecretStore()
            defaults.set("sk-ant-legacy", forKey: Self.legacyDefaultsKey)
            let store = makeStore(secrets: secrets, defaults: defaults)

            #expect(store.load() == "sk-ant-legacy")
            #expect(secrets.value == "sk-ant-legacy")
            #expect(defaults.string(forKey: Self.legacyDefaultsKey) == nil)

            // Second read comes from the Keychain, with no further migration.
            #expect(store.load() == "sk-ant-legacy")
            #expect(secrets.writeCount == 1)
        }
    }

    @Test("No key anywhere loads as empty and is not configured")
    func missingKeyLoadsEmpty() throws {
        try withScratchDefaults { defaults in
            let store = makeStore(secrets: InMemorySecretStore(), defaults: defaults)

            #expect(store.load().isEmpty)
            #expect(!store.hasKey())
        }
    }

    @Test("An empty stored value falls through rather than counting as a key")
    func emptyStoredValueIsNotAKey() throws {
        try withScratchDefaults { defaults in
            let store = makeStore(secrets: InMemorySecretStore(value: ""), defaults: defaults)

            #expect(store.load().isEmpty)
            #expect(!store.hasKey())
        }
    }

    // MARK: - Key shapes

    @Test(
        "Anthropic key shapes",
        arguments: [
            ("sk-ant-api03-abc123", true),
            ("sk-ant-abc123", true),
            ("sk-abc123", false),
            ("not-a-key", false)
        ]
    )
    func anthropicPrefixValidation(key: String, accepted: Bool) throws {
        try withScratchDefaults { defaults in
            let store = makeStore(
                secrets: InMemorySecretStore(value: key),
                defaults: defaults,
                prefixes: Self.anthropicPrefixes
            )

            #expect(store.hasKey() == accepted)
        }
    }

    @Test(
        "OpenAI key shapes",
        arguments: [
            ("sk-abc123", true),
            ("sk-proj-abc123", true),
            ("pk-abc123", false),
            ("not-a-key", false)
        ]
    )
    func openAIPrefixValidation(key: String, accepted: Bool) throws {
        try withScratchDefaults { defaults in
            let store = makeStore(
                secrets: InMemorySecretStore(value: key),
                defaults: defaults,
                prefixes: Self.openAIPrefixes
            )

            #expect(store.hasKey() == accepted)
        }
    }

    // MARK: - Saving and clearing

    @Test("Saving writes to the secret store")
    func saveWritesToSecretStore() throws {
        try withScratchDefaults { defaults in
            let secrets = InMemorySecretStore()
            let store = makeStore(secrets: secrets, defaults: defaults)

            store.save("sk-ant-api03-saved")

            #expect(secrets.value == "sk-ant-api03-saved")
            #expect(store.load() == "sk-ant-api03-saved")
            #expect(store.hasKey())
        }
    }

    @Test("Clearing empties the secret store and the legacy default")
    func clearRemovesBothCopies() throws {
        try withScratchDefaults { defaults in
            let secrets = InMemorySecretStore(value: "sk-ant-stored")
            defaults.set("sk-ant-legacy", forKey: Self.legacyDefaultsKey)
            let store = makeStore(secrets: secrets, defaults: defaults)

            store.clear()

            #expect(secrets.value == nil)
            #expect(secrets.deleteCount == 1)
            #expect(defaults.string(forKey: Self.legacyDefaultsKey) == nil)
            #expect(store.load().isEmpty)
        }
    }

    // MARK: - Shipped providers

    @Test("Shipped providers keep their key shapes and legacy defaults keys")
    func shippedProvidersAreConfiguredAsBefore() {
        #expect(APIKeyStore.anthropic.acceptedPrefixes == Self.anthropicPrefixes)
        #expect(APIKeyStore.anthropic.legacyDefaultsKey == UserDefaultsKeys.anthropicAPIKey)
        #expect(APIKeyStore.openAI.acceptedPrefixes == Self.openAIPrefixes)
        #expect(APIKeyStore.openAI.legacyDefaultsKey == UserDefaultsKeys.openAIAPIKey)
    }
}
