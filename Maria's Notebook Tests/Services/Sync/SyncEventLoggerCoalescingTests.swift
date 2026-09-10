import Foundation
import Testing
@testable import Maria_s_Notebook

/// The suite runs in parallel with every other suite, and a main-actor task
/// can wait seconds for a turn under that contention — so timing assertions
/// poll for the expected state instead of sleeping a fixed interval.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(10),
    _ condition: @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now > deadline { return }
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// The sync history log sits on the CloudKit hot path: every remote-change
/// notification and every CloudKit event writes to it. These pin the two
/// behaviours that keep it cheap — repeats fold into one row, and the
/// UserDefaults write is debounced — plus the on-disk compatibility.
@Suite("Sync event logger: coalescing and debounced writes")
@MainActor
struct SyncEventLoggerCoalescingTests {

    private struct Fixture {
        let logger: SyncEventLogger
        let defaults: UserDefaults
        let suiteName: String
        let storageKey = "SyncHistory.events.test"

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "sync-logger-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let logger = SyncEventLogger(
            defaults: defaults,
            storageKey: "SyncHistory.events.test",
            coalesceWindow: 30,
            saveDelay: .milliseconds(50)
        )
        return Fixture(logger: logger, defaults: defaults, suiteName: suiteName)
    }

    @Test("A burst of identical events folds into one row with a count")
    func repeatsFoldIntoOneEvent() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        for _ in 0..<100 {
            fixture.logger.log("cloudkit", status: "success", message: "Remote changes received")
        }
        #expect(fixture.logger.events.count == 1)
        #expect(fixture.logger.events.first?.count == 100)
    }

    @Test("A different message, status, or type starts a new row")
    func differentEventsStaySeparate() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.logger.log("cloudkit", status: "success", message: "Remote changes received")
        fixture.logger.log("cloudkit", status: "success", message: "Import completed")
        fixture.logger.log("cloudkit", status: "error", message: "Import completed")
        fixture.logger.log("calendar", status: "error", message: "Import completed")
        #expect(fixture.logger.events.count == 4)
        #expect(fixture.logger.events.allSatisfy { $0.count == 1 })
    }

    @Test("The window slides from the latest repeat; a quiet gap starts a new row")
    func repeatsOutsideWindowStartANewRow() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let start: Date = Date()
        let secondRepeat: Date = start.addingTimeInterval(29)
        let insideWindow: Date = start.addingTimeInterval(31)
        let afterQuietGap: Date = start.addingTimeInterval(62)
        let message = "Remote changes received"

        fixture.logger.now = { start }
        fixture.logger.log("cloudkit", status: "success", message: message)
        fixture.logger.now = { secondRepeat }
        fixture.logger.log("cloudkit", status: "success", message: message)
        #expect(fixture.logger.events.count == 1)
        #expect(fixture.logger.events.first?.timestamp == secondRepeat)
        // Two seconds after the second repeat is still inside the window.
        fixture.logger.now = { insideWindow }
        fixture.logger.log("cloudkit", status: "success", message: message)
        #expect(fixture.logger.events.count == 1)
        #expect(fixture.logger.events.first?.count == 3)
        // Thirty-one seconds of quiet is not.
        fixture.logger.now = { afterQuietGap }
        fixture.logger.log("cloudkit", status: "success", message: message)
        #expect(fixture.logger.events.count == 2)
        #expect(fixture.logger.events.first?.count == 1)
        #expect(fixture.logger.events.last?.count == 3)
    }

    @Test("The 50-row cap still holds for distinct events")
    func capHolds() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        for index in 0..<60 {
            fixture.logger.log("cloudkit", status: "success", message: "Event \(index)")
        }
        #expect(fixture.logger.events.count == 50)
        #expect(fixture.logger.events.first?.message == "Event 59")
    }

    @Test("Nothing is written until the save delay elapses, then the count survives a reload")
    func writesAreDebouncedAndRoundTrip() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        for _ in 0..<3 {
            fixture.logger.log("reminders", status: "success", message: "Reminders sync completed")
        }
        #expect(fixture.defaults.data(forKey: fixture.storageKey) == nil)

        try await waitUntil { fixture.defaults.data(forKey: fixture.storageKey) != nil }
        #expect(fixture.defaults.data(forKey: fixture.storageKey) != nil)

        let reloaded = SyncEventLogger(defaults: fixture.defaults, storageKey: fixture.storageKey)
        #expect(reloaded.events.count == 1)
        #expect(reloaded.events.first?.count == 3)
    }

    @Test("flushPendingSave writes immediately")
    func flushWritesNow() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.logger.log("calendar", status: "started", message: "Calendar sync started")
        fixture.logger.flushPendingSave()
        #expect(fixture.defaults.data(forKey: fixture.storageKey) != nil)
    }

    @Test("Rows written before the count column decode as one occurrence")
    func legacyRowsDecode() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let legacy = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","timestamp":0,\
        "type":"cloudkit","status":"success","message":"Import completed"}]
        """
        fixture.defaults.set(Data(legacy.utf8), forKey: fixture.storageKey)
        let reloaded = SyncEventLogger(defaults: fixture.defaults, storageKey: fixture.storageKey)
        #expect(reloaded.events.count == 1)
        #expect(reloaded.events.first?.count == 1)
        #expect(reloaded.events.first?.message == "Import completed")
    }
}

/// `.NSPersistentStoreRemoteChange` arrives once per imported batch. The
/// status service must handle a whole burst once, after it goes quiet.
@Suite("CloudKit sync status: remote-change debounce")
@MainActor
struct RemoteChangeDebounceTests {

    @Test("Fifty notifications in a burst run the handler once")
    func burstRunsOnce() async throws {
        let service = CloudKitSyncStatusService()
        service.remoteChangeDebounce = .milliseconds(100)
        for _ in 0..<50 {
            service.scheduleRemoteChangeHandling()
        }
        #expect(service.remoteChangeHandlingCount == 0)
        try await waitUntil { service.remoteChangeHandlingCount >= 1 }
        #expect(service.remoteChangeHandlingCount == 1)
        #expect(service.lastOperation == "Remote changes received")
        // Nothing else was queued behind it.
        try await Task.sleep(for: .milliseconds(300))
        #expect(service.remoteChangeHandlingCount == 1)
    }

    @Test("Notifications separated by more than the quiet period each run")
    func separatedBurstsEachRun() async throws {
        let service = CloudKitSyncStatusService()
        service.remoteChangeDebounce = .milliseconds(50)
        service.scheduleRemoteChangeHandling()
        try await waitUntil { service.remoteChangeHandlingCount >= 1 }
        #expect(service.remoteChangeHandlingCount == 1)
        service.scheduleRemoteChangeHandling()
        try await waitUntil { service.remoteChangeHandlingCount >= 2 }
        #expect(service.remoteChangeHandlingCount == 2)
    }
}
