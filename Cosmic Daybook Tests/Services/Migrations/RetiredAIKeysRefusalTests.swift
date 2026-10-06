import Foundation
import os
import Security
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #52. The retired-keys cleanup ran on the main
// thread at launch, and a device whose Keychain kept refusing (locked, or an
// item this build may not touch) retried it, on the main thread, at every
// launch for good. It now runs off the main thread, and three launches that
// end in a refusal count it done.

@Suite("Retired AI keys cleanup gives up after three refusals")
struct RetiredAIKeysRefusalTests {

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "RetiredAIKeysRefusalTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @Test("Three launches refused by the Keychain count the cleanup done", arguments: [
        errSecInteractionNotAllowed, errSecAuthFailed
    ])
    func threeRefusalsCountDone(status: OSStatus) throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!RetiredAIKeysCleanup.runIfNeeded(defaults: defaults) { _, _ in status })
        #expect(!RetiredAIKeysCleanup.runIfNeeded(defaults: defaults) { _, _ in status })
        #expect(!defaults.bool(forKey: UserDefaultsKeys.retiredAIKeysRemovedV1))
        #expect(RetiredAIKeysCleanup.runIfNeeded(defaults: defaults) { _, _ in status })
        #expect(defaults.bool(forKey: UserDefaultsKeys.retiredAIKeysRemovedV1))

        let after = RetiredAIKeysCleanup.runIfNeeded(defaults: defaults) { _, _ in
            Issue.record("A launch after giving up must not touch the Keychain")
            return errSecSuccess
        }
        #expect(!after)
    }

    @Test("Other failures don't count toward giving up")
    func otherFailuresKeepTrying() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        for _ in 0..<4 {
            #expect(!RetiredAIKeysCleanup.runIfNeeded(defaults: defaults) { _, _ in errSecParam })
        }
        #expect(!defaults.bool(forKey: UserDefaultsKeys.retiredAIKeysRemovedV1))
    }

    @Test("The launch's call reaches the Keychain off the main thread")
    @MainActor
    func launchCallRunsOffTheMainThread() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calledOnMain = OSAllocatedUnfairLock(initialState: [Bool]())

        let finished = await RetiredAIKeysCleanup.runOffMainThread(defaultsSuite: suite) { _, _ in
            calledOnMain.withLock { $0.append(Thread.isMainThread) }
            return errSecItemNotFound
        }

        #expect(finished)
        #expect(calledOnMain.withLock { $0 } == [false, false])
        #expect(defaults.bool(forKey: UserDefaultsKeys.retiredAIKeysRemovedV1))
    }
}
