import Foundation
import EventKit
import Testing
@testable import CosmicDaybook

/// Main-actor tasks can wait seconds for a turn while the whole suite runs
/// in parallel, so these poll for the state they expect, with a deadline,
/// instead of sleeping a fixed interval.
@MainActor
private func waitUntil(timeout: Duration = .seconds(30), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// When each handler run happened.
@MainActor
private final class HandlerRuns {
    private(set) var times: [ContinuousClock.Instant] = []

    func record() {
        times.append(ContinuousClock.now)
    }
}

/// UserDefaults of the tests' own, so a service under test never reads or
/// writes the app's EventKit settings.
private struct IsolatedDefaults {
    let suiteName = "EventKitChangeHandlingTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// The calendar daemon posts `.EKEventStoreChanged` twice when it refreshes
/// its accounts. The observer must run its handler once per burst, after the
/// store goes quiet, where it used to run it once per notification.
@Suite("EventKit change observer: trailing coalescing")
@MainActor
struct EventKitChangeObserverTests {

    @Test("Five changes inside the quiet period run the handler once, after it")
    func burstRunsHandlerOnceAfterQuietPeriod() async throws {
        let quietPeriod: Duration = .milliseconds(200)
        let observer = EventKitChangeObserver(quietPeriod: quietPeriod)
        let store = NSObject()
        let runs = HandlerRuns()
        observer.start(observing: store) { runs.record() }
        defer { observer.stop() }

        for _ in 0..<5 {
            NotificationCenter.default.post(name: .EKEventStoreChanged, object: store)
        }
        let lastChange = ContinuousClock.now

        #expect(await waitUntil { !runs.times.isEmpty && !observer.hasPendingChange })
        // Nothing is pending once the handler has run, so no second run can follow.
        #expect(runs.times.count == 1)
        let ranAt = try #require(runs.times.first)
        #expect(ranAt - lastChange >= quietPeriod)
    }

    @Test("A change after the store went quiet runs the handler again")
    func laterChangeRunsAgain() async {
        let observer = EventKitChangeObserver(quietPeriod: .milliseconds(50))
        let store = NSObject()
        let runs = HandlerRuns()
        observer.start(observing: store) { runs.record() }
        defer { observer.stop() }

        NotificationCenter.default.post(name: .EKEventStoreChanged, object: store)
        #expect(await waitUntil { runs.times.count == 1 && !observer.hasPendingChange })
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: store)
        #expect(await waitUntil { runs.times.count == 2 && !observer.hasPendingChange })
        #expect(runs.times.count == 2)
    }

    @Test("Stopping drops a change that is still waiting out the quiet period")
    func stopDropsPendingChange() async {
        let observer = EventKitChangeObserver(quietPeriod: .seconds(60))
        let store = NSObject()
        let runs = HandlerRuns()
        observer.start(observing: store) { runs.record() }

        NotificationCenter.default.post(name: .EKEventStoreChanged, object: store)
        #expect(await waitUntil { observer.hasPendingChange })
        observer.stop()
        #expect(!observer.hasPendingChange)
        #expect(!observer.isObserving)
        #expect(runs.times.isEmpty)
    }
}

/// An automatic sync the 10-minute throttle skips must not move
/// `lastSyncTime`: stamping it anyway pushed the next real sync back on every
/// change, so a store that kept changing never synced. The throttled path
/// returns before EventKit is touched, so the services run here as they are.
@Suite("EventKit sync throttle: a skipped sync leaves the clock alone")
@MainActor
struct EventKitSyncThrottleTests {

    @Test("A throttled automatic calendar sync keeps the last sync time")
    func throttledCalendarSyncKeepsLastSyncTime() async throws {
        let isolated = try IsolatedDefaults()
        defer { isolated.cleanUp() }
        isolated.defaults.set(["school-calendar"], forKey: UserDefaultsKeys.calendarSyncIdentifiers)
        let service = CalendarSyncService(context: try CoreDataTestHelpers.makeContext(), defaults: isolated.defaults)
        service.authorizationStatus = .fullAccess
        let earlier = Date(timeIntervalSinceNow: -60)
        service.lastSyncTime = earlier

        await service.handleEventStoreChanged()

        #expect(service.lastSyncTime == earlier)
        #expect(!service.isSyncing)
        #expect(service.lastSyncError == nil)
    }

    @Test("A direct sync inside the throttle window reports that it did not run")
    func throttledSyncReportsSkip() async throws {
        let isolated = try IsolatedDefaults()
        defer { isolated.cleanUp() }
        let calendar = CalendarSyncService(context: try CoreDataTestHelpers.makeContext(), defaults: isolated.defaults)
        let earlier = Date(timeIntervalSinceNow: -60)
        calendar.lastSyncTime = earlier

        #expect(try await calendar.syncEvents() == false)
        #expect(calendar.lastSyncTime == earlier)
    }
}

/// Danny decided (2026-09-25) that a list EventKit no longer has pauses
/// listening for store changes until the setting changes; a new choice
/// resumes listening and is tried once. Reminders sync was retired
/// 2026-11-03; the calendar mirror keeps the rule.
@Suite("EventKit: a missing list pauses change observation")
@MainActor
struct EventKitChangeListeningTests {

    @Test("A missing list pauses listening until the setting changes")
    func pauseAndResume() {
        var listening = EventKitChangeListening()
        #expect(listening.shouldListen(hasFullAccess: true, isListConfigured: true))

        let firstMissStops = listening.pause()
        #expect(firstMissStops)
        #expect(!listening.shouldListen(hasFullAccess: true, isListConfigured: true))
        // Later misses find listening already stopped.
        let laterMissStops = listening.pause()
        #expect(!laterMissStops)
        #expect(listening.isPaused)

        // The setting changed: listen again, and try the new choice once.
        let settingChangeRetries = listening.resume()
        #expect(settingChangeRetries)
        #expect(listening.shouldListen(hasFullAccess: true, isListConfigured: true))
        // A change while listening asks for no extra attempt.
        let changeWhileListeningRetries = listening.resume()
        #expect(!changeWhileListeningRetries)
    }

    @Test("Listening still needs access and a configured list")
    func listeningNeedsAccessAndList() {
        let listening = EventKitChangeListening()
        #expect(!listening.shouldListen(hasFullAccess: false, isListConfigured: true))
        #expect(!listening.shouldListen(hasFullAccess: true, isListConfigured: false))
    }

}
