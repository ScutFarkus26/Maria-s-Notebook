import Foundation
import Security
import Testing
@testable import CosmicDaybook

/// The one-time removal of the retired Claude/OpenAI keys and model choices.
/// Every test uses its own defaults suite and a fake Keychain, so the real
/// Keychain is never touched.
@Suite("Retired AI keys cleanup")
struct RetiredAIKeysCleanupTests {

    private func makeDefaults() throws -> UserDefaults {
        let suite = "RetiredAIKeysCleanupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Deletes both Keychain items and every leftover preference, once")
    func removesEverythingOnce() throws {
        let defaults = try makeDefaults()
        for key in RetiredAIKeysCleanup.defaultsKeys {
            defaults.set("left over", forKey: key)
        }
        defaults.set(true, forKey: UserDefaultsKeys.aiAllowAutomaticPrivateCloud)
        var deleted: [String] = []

        let ran = RetiredAIKeysCleanup.runIfNeeded(defaults: defaults) { service, account in
            #expect(service == RetiredAIKeysCleanup.keychainService)
            deleted.append(account)
            return account == "openAIAPIKey" ? errSecItemNotFound : errSecSuccess
        }

        #expect(ran)
        #expect(deleted == ["anthropicAPIKey", "openAIAPIKey"])
        #expect(RetiredAIKeysCleanup.defaultsKeys.allSatisfy { defaults.object(forKey: $0) == nil })
        // The one AI setting that still exists is left alone.
        #expect(defaults.bool(forKey: UserDefaultsKeys.aiAllowAutomaticPrivateCloud))

        let again = RetiredAIKeysCleanup.runIfNeeded(defaults: defaults) { _, _ in
            Issue.record("A second launch must not touch the Keychain")
            return errSecSuccess
        }
        #expect(!again)
    }

    @Test("A Keychain refusal leaves the cleanup to run again next launch")
    func retriesAfterKeychainFailure() throws {
        let defaults = try makeDefaults()

        let failed = RetiredAIKeysCleanup.runIfNeeded(defaults: defaults) { _, _ in errSecInteractionNotAllowed }
        #expect(!failed)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.retiredAIKeysRemovedV1))

        let retried = RetiredAIKeysCleanup.runIfNeeded(defaults: defaults) { _, _ in errSecSuccess }
        #expect(retried)
        #expect(defaults.bool(forKey: UserDefaultsKeys.retiredAIKeysRemovedV1))
    }
}
