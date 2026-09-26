import Testing
@testable import CosmicDaybook

// MARK: - One iCloud account listener
//
// `CloudKitSyncStatusService.configure` restarts account monitoring every time
// it runs, and it ran once per main window. `startICloudAccountMonitoring`
// overwrote its `.CKAccountChanged` listener task without cancelling it, so
// every extra window left one more listener running for the whole session,
// each of which asked CloudKit for the account status on every change. The
// listener is now cancelled before it is replaced. These tests start only the
// listener (no account-status request), so nothing here talks to CloudKit.

@Suite("iCloud account listener")
@MainActor
struct CloudKitHealthCheckListenerTests {

    @Test("Restarting the listener cancels the one it replaces", .timeLimit(.minutes(1)))
    func restartReplacesListener() async throws {
        let healthCheck = CloudKitHealthCheck()
        healthCheck.listenForAccountChanges()
        let first = try #require(healthCheck.iCloudAccountTask)

        healthCheck.listenForAccountChanges()
        let second = try #require(healthCheck.iCloudAccountTask)

        #expect(first.isCancelled)
        #expect(!second.isCancelled)
        // The replaced listener's loop actually ends; it does not sit waiting
        // for the next account change. (A leak would hang here until the limit.)
        await first.value

        second.cancel()
        await second.value
    }

    @Test("Three restarts leave exactly one live listener", .timeLimit(.minutes(1)))
    func repeatedRestartsLeaveOne() async throws {
        let healthCheck = CloudKitHealthCheck()
        var replaced: [Task<Void, Never>] = []
        for _ in 0..<3 {
            if let current = healthCheck.iCloudAccountTask { replaced.append(current) }
            healthCheck.listenForAccountChanges()
        }
        let live = try #require(healthCheck.iCloudAccountTask)

        #expect(replaced.count == 2)
        #expect(replaced.allSatisfy { $0.isCancelled })
        #expect(!live.isCancelled)
        for task in replaced { await task.value }

        live.cancel()
        await live.value
    }
}
