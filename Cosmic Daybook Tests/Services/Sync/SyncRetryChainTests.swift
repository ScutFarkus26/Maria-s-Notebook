import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - One failure chain, one report (bug hunt 2026-11-02, #4)
//
// Every failed import or export used to spend a retry attempt, so after five
// failed events every further one called `onMaxRetriesReached`: a persisted
// error, a history row and a five-second toast each, about two minutes of
// stacked toasts while a guide marks 25 children. An attempt now counts once
// it has run, events that arrive while one waits add nothing, and the chain's
// end is reported once until a success resets it.

/// Polls until `condition` holds or 10 s pass; the test's own expectations then decide.
@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
}

@Suite("Sync retries: one chain, one report", .serialized)
@MainActor
struct SyncRetryChainTests {

    @Test("Failed events that arrive while a retry waits spend no attempts")
    func burstWhileWaitingSpendsOneAttempt() async throws {
        let logic = SyncRetryLogic(baseRetryDelay: 0.05)
        var runs = 0
        var reports = 0
        for _ in 0..<25 {
            logic.scheduleRetry(canRetry: { true }, syncAction: { runs += 1; return true }, onMaxRetriesReached: {
                reports += 1
            })
        }
        try await waitUntil { runs == 1 && !logic.hasPendingRetry }
        #expect(runs == 1)
        #expect(logic.retryAttempt == 1)
        #expect(reports == 0)
    }

    @Test("Five retries that ran, then more failures: the end is reported once")
    func exhaustionReportedOncePerChain() async throws {
        let logic = SyncRetryLogic(baseRetryDelay: 0.001)
        var runs = 0
        var reports = 0
        // Each pass is one failed event that finds no retry waiting.
        for _ in 0..<12 {
            logic.scheduleRetry(canRetry: { true }, syncAction: { runs += 1; return true }, onMaxRetriesReached: {
                reports += 1
            })
            try await waitUntil { !logic.hasPendingRetry }
        }
        #expect(runs == 5)
        #expect(reports == 1)
        #expect(logic.exhaustionReported)
        #expect(!logic.hasPendingRetry)

        // A success (or Sync Now's clear) ends the chain; the next one may report again.
        logic.resetRetryCount()
        #expect(!logic.exhaustionReported)
        for _ in 0..<7 {
            logic.scheduleRetry(canRetry: { true }, syncAction: { runs += 1; return true }, onMaxRetriesReached: {
                reports += 1
            })
            try await waitUntil { !logic.hasPendingRetry }
        }
        #expect(runs == 10)
        #expect(reports == 2)
    }

    @Test("Retries whose save fails go on by themselves and report once")
    func failedSavesChainAndReportOnce() async throws {
        let logic = SyncRetryLogic(baseRetryDelay: 0.001)
        var runs = 0
        var reports = 0
        let action: () async -> Bool = { runs += 1; return false }
        logic.scheduleRetry(canRetry: { true }, syncAction: action, onMaxRetriesReached: { reports += 1 })
        try await waitUntil { reports == 1 && !logic.hasPendingRetry }
        #expect(runs == 5)
        #expect(reports == 1)

        for _ in 0..<5 {
            logic.scheduleRetry(canRetry: { true }, syncAction: action, onMaxRetriesReached: { reports += 1 })
        }
        #expect(reports == 1)
        #expect(runs == 5)
        #expect(!logic.hasPendingRetry)
    }

    @Test("The network coming back starts the attempts again, not the report")
    func networkBackKeepsTheReportSaid() async throws {
        let logic = SyncRetryLogic(baseRetryDelay: 0.001)
        var reports = 0
        let action: () async -> Bool = { false }
        logic.scheduleRetry(canRetry: { true }, syncAction: action, onMaxRetriesReached: { reports += 1 })
        try await waitUntil { reports == 1 && !logic.hasPendingRetry }

        var retriedNow = false
        logic.retryPendingSync(canRetry: { true }, hasPendingWork: { true }, syncAction: { retriedNow = true })
        try await waitUntil { retriedNow }
        #expect(logic.retryAttempt == 0)

        logic.scheduleRetry(canRetry: { true }, syncAction: action, onMaxRetriesReached: { reports += 1 })
        try await waitUntil { logic.retryAttempt == 5 && !logic.hasPendingRetry }
        #expect(logic.retryAttempt == 5)
        #expect(reports == 1)
    }

    @Test("A storm of failed share exports logs \u{201C}kept failing\u{201D} once")
    func serviceReportsOnceForAStorm() async throws {
        let defaults = UserDefaults.standard
        let keys = [
            UserDefaultsKeys.cloudKitLastSyncError,
            UserDefaultsKeys.cloudKitLastSyncErrorDetail,
            UserDefaultsKeys.cloudKitLastSyncErrorKind,
            UserDefaultsKeys.cloudKitErrorLog,
            UserDefaultsKeys.cloudKitLastErrorDescription
        ]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }

        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let service = CloudKitSyncStatusService(coreDataStack: stack, retryLogic: SyncRetryLogic(baseRetryDelay: 0.001))
        service.syncedStoreResolver = { identifier in
            SyncedStore(
                identifier: identifier, notebookIdentifier: "private-store", classroomShareIdentifier: "shared-store"
            )
        }
        defer { service.retryLogic.resetRetryCount() }
        let started = Date()
        // Rows from this test only (the history keeps 50, so older ones can fall off), repeats folded in.
        let gaveUpCount = {
            SyncEventLogger.shared.events
                .filter { $0.message == "Sync kept failing, so it stopped trying for now" && $0.timestamp >= started }
                .reduce(0) { $0 + $1.count }
        }
        let refused = NSError(domain: CKErrorDomain, code: CKError.Code.serverRejectedRequest.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Rejected"
        ])

        for _ in 0..<25 {
            service.handleCloudKitEvent(
                type: .export, isFinished: true, succeeded: false, error: refused,
                startDate: Date(), storeIdentifier: "shared-store"
            )
            try await waitUntil { !service.retryLogic.hasPendingRetry }
        }
        // The report hops through a Task; give it its turn.
        try await waitUntil { gaveUpCount() > 0 }
        try await Task.sleep(for: .milliseconds(50))

        #expect(gaveUpCount() == 1)
        #expect(service.retryLogic.exhaustionReported)
    }
}
