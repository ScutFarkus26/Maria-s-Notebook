import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - Sync status and the classroom share (bug hunt 2026-10-10, Part 1 #1–#8)
//
// What stops or holds filing into the classroom share must hold in more
// cases, never fewer: before `configure` (a Siri launch has no window), after
// a setup that failed for the network, and across another Apple Account
// signing in. A single "no account" read right at login no longer pauses
// filing until reopening, and the filing step is woken when sync lets it file.

private func ckError(_ code: CKError.Code, _ message: String = "CloudKit error") -> NSError {
    NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
}

private let noAccount = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
    NSLocalizedDescriptionKey: "Unable to initialize without an iCloud account."
])

private let setupThrew = NSError(domain: NSCocoaErrorDomain, code: 134_060, userInfo: [
    NSLocalizedDescriptionKey: "A Core Data error occurred."
])

/// The defaults these tests' services write, restored after each test.
@MainActor
private func withSavedDefaults(_ body: () async throws -> Void) async rethrows {
    let keys = [
        UserDefaultsKeys.cloudKitLastSuccessfulSyncDate,
        UserDefaultsKeys.cloudKitLastSyncError,
        UserDefaultsKeys.cloudKitLastSyncErrorDetail,
        UserDefaultsKeys.cloudKitLastSyncErrorKind,
        UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate,
        UserDefaultsKeys.cloudKitLastSuccessfulImportStartByStore,
        UserDefaultsKeys.cloudKitLastSuccessfulExportStartByStore,
        UserDefaultsKeys.cloudKitErrorLog,
        UserDefaultsKeys.cloudKitLastErrorDescription,
        FirstDownloadGate.key
    ]
    let defaults = UserDefaults.standard
    let saved = keys.map { defaults.object(forKey: $0) }
    defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
    try await body()
}

/// Polls until `condition` holds or 5 s pass; the test's own expectations then decide.
@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// What a test service did: account asks, wakes of the filing step.
@MainActor
private final class Seen {
    var asks = 0
    var wakes = 0
    var waitsForImportAfterPin = false
}

/// A service naming "private-store" the notebook and "shared-store" the
/// classroom share. Each account ask answers with the next of `answers` (the
/// last one again once they run out); wakes of the filing step are counted.
@MainActor
private func makeService(answers: [CKAccountStatus] = [.available], seen: Seen = Seen()) -> CloudKitSyncStatusService {
    let service = CloudKitSyncStatusService()
    service.syncedStoreResolver = { identifier in
        SyncedStore(
            identifier: identifier, notebookIdentifier: "private-store", classroomShareIdentifier: "shared-store"
        )
    }
    service.accountStatus = {
        seen.asks += 1
        return answers[min(seen.asks, answers.count) - 1]
    }
    service.filingHooks.waitBeforeAccountRecheck = {}
    service.filingHooks.wakeFiling = { seen.wakes += 1 }
    service.filingHooks.waitsForImportAfterPin = { seen.waitsForImportAfterPin }
    return service
}

/// An event as it arrives from CloudKit's stream (`receive`). A service not
/// yet configured (a launch with no window) keeps it for later.
@MainActor
private func arrive(
    _ service: CloudKitSyncStatusService,
    _ type: NSPersistentCloudKitContainer.EventType,
    store: String,
    error: NSError? = nil,
    failed: Bool? = nil,
    startDate: Date = Date()
) {
    service.receive(CloudKitEventValues(
        type: type, isFinished: true, succeeded: !(failed ?? (error != nil)), error: error,
        startDate: startDate, storeIdentifier: store
    ))
}

/// An event handed straight to the handlers, as after `configure`.
@MainActor
private func finish(
    _ service: CloudKitSyncStatusService,
    _ type: NSPersistentCloudKitContainer.EventType,
    store: String,
    error: NSError? = nil
) {
    service.handleCloudKitEvent(
        type: type, isFinished: true, succeeded: error == nil, error: error,
        startDate: Date(), storeIdentifier: store
    )
}

/// A wait the test ends by hand.
@MainActor
private final class ManualWait {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@Suite("Sync status: stops and holds for the classroom share (2026-10-10)", .serialized)
@MainActor
struct SyncStatusFix1010ATests {

    // MARK: #1 Before configure

    @Test("With no window, a setup that failed for anything but the account stops filing as it arrives")
    func earlyFailedSetupStopsFiling() async {
        await withSavedDefaults {
            let seen = Seen()
            let service = makeService(seen: seen)
            #expect(!service.handlesCloudKitEvents, "a Siri launch never configures")
            let failedAt = Date()
            arrive(service, .setup, store: "private-store", error: setupThrew, startDate: failedAt)
            #expect(service.mirroringDelegateFailed)
            #expect(service.stoppedStores == [.notebook])
            #expect(service.shareFilingStopReason == "iCloud stopped syncing")

            // A success from before the failure proves nothing; the store's own later one clears it.
            arrive(service, .export, store: "private-store", startDate: failedAt.addingTimeInterval(-1))
            arrive(service, .export, store: "shared-store", startDate: failedAt.addingTimeInterval(1))
            #expect(service.mirroringDelegateFailed)
            arrive(service, .export, store: "private-store", startDate: failedAt.addingTimeInterval(1))
            #expect(!service.mirroringDelegateFailed)
            #expect(seen.wakes == 1, "what waited goes in once nothing stops it")
        }
    }

    @Test("configure hands the same events over and ends where they did; another stack's early stops go")
    func configureReplaysToTheSameEnd() async throws {
        try await withSavedDefaults {
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            let service = makeService()
            defer { service.retryLogic.resetRetryCount() }
            service.beginEarlyEventCapture(for: stack)
            let failedAt = Date()
            arrive(service, .setup, store: "shared-store", error: setupThrew, startDate: failedAt)
            arrive(service, .setup, store: "private-store", error: setupThrew, startDate: failedAt)
            arrive(service, .export, store: "shared-store", startDate: failedAt.addingTimeInterval(1))
            #expect(service.stoppedStores == [.notebook])

            service.startHandlingCloudKitEvents(for: stack)
            #expect(service.stoppedStores == [.notebook], "the replay ends where the events did")
            #expect(service.bufferedEvents.isEmpty)

            let other = makeService()
            other.beginEarlyEventCapture(for: stack)
            arrive(other, .setup, store: "private-store", error: setupThrew)
            other.markMirroringStopped(byAttachToStoreWithIdentifier: "shared-store")
            other.startHandlingCloudKitEvents(for: try CoreDataTestHelpers.makeInMemoryStack())
            #expect(other.stoppedStores == [.classroomShare], "only the attach's stop stays")
        }
    }

    // MARK: #2 A setup that failed for the network

    @Test("A setup that failed for the network, a busy server or no stated reason holds filing until set up and synced")
    func transientSetupFailureHolds() async throws {
        try await withSavedDefaults {
            let failures: [NSError?] = [
                ckError(.networkUnavailable), ckError(.networkFailure), ckError(.zoneBusy),
                ckError(.requestRateLimited), ckError(.serviceUnavailable), ckError(.serverResponseLost),
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), nil
            ]
            for error in failures {
                let seen = Seen()
                let service = makeService(answers: [.noAccount], seen: seen)
                arrive(service, .setup, store: "private-store", error: error, failed: true)
                #expect(service.shareFilingHold == .untilICloudReady, "\(String(describing: error))")
                #expect(service.shareFilingStopReason == "iCloud isn't ready yet")
                #expect(!service.mirroringDelegateFailed, "not a dead delegate")

                arrive(service, .export, store: "shared-store")
                arrive(service, .setup, store: "private-store")
                #expect(service.shareFilingHold == .untilICloudReady, "set up, but nothing synced since")
                arrive(service, .export, store: "private-store")
                #expect(service.shareFilingHold == nil)
                #expect(seen.wakes == 1)
                try await Task.sleep(for: .milliseconds(20))
                #expect(seen.asks == 0, "the account isn't asked about")
                #expect(!service.shareFilingPausedUntilReopen)
            }
        }
    }

    // MARK: #4 The account check after 134400

    @Test("One no-account answer at once doesn't pause filing until reopening; the second, after the wait, does")
    func oneNoAccountAnswerDoesNotLatch() async throws {
        try await withSavedDefaults {
            let seen = Seen()
            let service = makeService(answers: [.noAccount], seen: seen)
            let wait = ManualWait()
            service.filingHooks.waitBeforeAccountRecheck = { await wait.wait() }
            arrive(service, .setup, store: "private-store", error: noAccount)
            try await waitUntil { wait.isWaiting }
            #expect(seen.asks == 1)
            #expect(!service.shareFilingPausedUntilReopen)
            #expect(service.shareFilingHold == .untilICloudReady, "filing waits all the same")

            wait.release()
            try await waitUntil { service.shareFilingPausedUntilReopen }
            #expect(seen.asks == 2)
            #expect(service.shareFilingHold == .untilReopen)
        }
    }

    @Test("134400 at login, then an account there when asked again: no pause; setup and an import lift the hold")
    func accountThereOnRecheckDoesNotLatch() async throws {
        try await withSavedDefaults {
            let seen = Seen()
            let service = makeService(answers: [.noAccount, .available], seen: seen)
            arrive(service, .setup, store: "private-store", error: noAccount)
            try await waitUntil { seen.asks == 2 }
            try await Task.sleep(for: .milliseconds(50))
            #expect(seen.asks == 2)
            #expect(!service.shareFilingPausedUntilReopen)
            #expect(service.shareFilingHold == .untilICloudReady)

            arrive(service, .setup, store: "private-store")
            arrive(service, .import, store: "private-store")
            #expect(service.shareFilingHold == nil)
        }
    }

    @Test("Still no account on the second ask, but the store set up meanwhile: no pause")
    func storeSetUpDuringTheWaitDoesNotLatch() async throws {
        try await withSavedDefaults {
            let seen = Seen()
            let service = makeService(answers: [.noAccount], seen: seen)
            service.filingHooks.waitBeforeAccountRecheck = { [weak service] in
                guard let service else { return }
                arrive(service, .setup, store: "private-store")
            }
            arrive(service, .setup, store: "private-store", error: noAccount)
            try await waitUntil { seen.asks == 2 }
            try await Task.sleep(for: .milliseconds(50))
            #expect(!service.shareFilingPausedUntilReopen)
            #expect(service.accountNotReadyStores["private-store"] == .awaitingSync)
        }
    }

    @Test("With no setup event back, an import that began after the failed setup lifts the hold; an export doesn't")
    func laterImportLiftsTheHold() async {
        await withSavedDefaults {
            let seen = Seen()
            let service = makeService(seen: seen)
            let failedAt = Date()
            arrive(service, .setup, store: "private-store", error: ckError(.accountTemporarilyUnavailable),
                   startDate: failedAt)
            #expect(service.shareFilingHold == .untilICloudReady)

            arrive(service, .import, store: "private-store", startDate: failedAt.addingTimeInterval(-5))
            #expect(service.shareFilingHold == .untilICloudReady, "began before the setup failed")
            arrive(service, .export, store: "private-store", startDate: failedAt.addingTimeInterval(5))
            #expect(service.shareFilingHold == .untilICloudReady, "an export alone doesn't lift it")
            arrive(service, .import, store: "shared-store", startDate: failedAt.addingTimeInterval(5))
            #expect(service.shareFilingHold == .untilICloudReady, "another store's import says nothing")

            arrive(service, .import, store: "private-store", startDate: failedAt.addingTimeInterval(5))
            #expect(service.shareFilingHold == nil)
            #expect(service.setupFailedAt.isEmpty)
            #expect(seen.wakes == 1)
        }
    }

    // MARK: #5 Waking the filing step

    @Test("A notebook import while the guard waits for one wakes filing; the share's, or with no wait, doesn't")
    func notebookImportWakesFiling() async {
        await withSavedDefaults {
            let seen = Seen()
            let service = makeService(seen: seen)
            seen.waitsForImportAfterPin = true
            finish(service, .import, store: "shared-store")
            finish(service, .export, store: "private-store")
            #expect(seen.wakes == 0)
            finish(service, .import, store: "private-store")
            #expect(seen.wakes == 1)

            seen.waitsForImportAfterPin = false
            finish(service, .import, store: "private-store")
            #expect(seen.wakes == 1)
        }
    }

    @Test("A stop clearing wakes filing, unless a hold still keeps it waiting")
    func clearedStopWakesFiling() async {
        await withSavedDefaults {
            let seen = Seen()
            let service = makeService(seen: seen)
            finish(service, .setup, store: "private-store", error: setupThrew)
            #expect(service.mirroringDelegateFailed)
            finish(service, .export, store: "private-store")
            #expect(!service.mirroringDelegateFailed)
            #expect(seen.wakes == 1)

            service.accountNotReadyStores = ["shared-store": .awaitingSetup]
            finish(service, .setup, store: "private-store", error: setupThrew)
            finish(service, .export, store: "private-store")
            #expect(!service.mirroringDelegateFailed)
            #expect(seen.wakes == 1, "the hold still keeps filing waiting")
        }
    }

    // MARK: #8 Another Apple Account

    @Test("Another account keeps a stop an attach found, not one an event set; a later success still clears it")
    func newAccountKeepsAttachStops() async {
        await withSavedDefaults {
            let service = makeService()
            finish(service, .setup, store: "shared-store", error: setupThrew)
            service.markMirroringStopped(byAttachToStoreWithIdentifier: "private-store")
            #expect(service.stoppedStores == [.notebook, .classroomShare])

            service.resetForNewAccount()
            #expect(service.stoppedStores == [.notebook])
            #expect(service.mirroringDelegateFailed)

            finish(service, .export, store: "private-store")
            #expect(!service.mirroringDelegateFailed)
            service.resetForNewAccount()
            #expect(!service.mirroringDelegateFailed, "cleared stays cleared")
        }
    }

    // MARK: #6 and #7 What an attach and the status say

    @Test("Why filing stops reads plainly after \u{201C}couldn't be added because\u{201D}; nil when nothing stops it")
    func stopReasonReadsPlainly() {
        let healthy = CloudKitSyncStatusService()
        #expect(healthy.shareFilingStopReason == nil)
        let held = CloudKitSyncStatusService()
        held.accountNotReadyStores = ["private-store": .awaitingSetup]
        #expect(held.shareFilingStopReason == "iCloud isn't ready yet")
        held.shareFilingPausedUntilReopen = true
        #expect(held.shareFilingStopReason == "you weren't signed in to iCloud when the notebook opened")
        held.markMirroringStopped(by: .notebook)
        #expect(held.shareFilingStopReason == "iCloud stopped syncing")

        #expect(CloudKitSyncStatusService.shareFilingPausedMessage
            == "You weren't signed in to iCloud when the notebook opened. "
                + "Sign in to iCloud, then quit and reopen the notebook.")
        #expect(!CloudKitSyncStatusService.shareFilingPausedMessage.contains("wasn't ready"))
    }
}
