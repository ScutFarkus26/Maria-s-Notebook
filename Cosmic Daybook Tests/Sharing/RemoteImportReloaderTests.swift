import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The Daybook Assistant's attendance screen reloads through this when the
// class arrives from iCloud. A first download is a burst of imports, so the
// reload must run once per burst, and never under a sheet that is editing a row.

@Suite("Remote Import Reloader")
@MainActor
struct RemoteImportReloaderTests {

    private final class Counter {
        var reloads = 0
    }

    /// Returns at once, so a reload comes due as soon as its task runs. With a
    /// real 30 ms sleep, the full parallel suite's heavy main-actor tests held
    /// that task past a two-second wait (2026-09-30: 10–14 s).
    private static let noWait: RemoteImportReloader.Sleep = { _ in }

    /// Waits for `condition`. The deadline is generous because the full
    /// parallel suite can starve the main actor for many seconds; a passing
    /// run returns as soon as the condition holds.
    private func waitFor(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("a burst of imports reloads once, after it settles")
    func burstReloadsOnce() async {
        let counter = Counter()
        let reloader = RemoteImportReloader(delay: .milliseconds(30), sleep: Self.noWait) { counter.reloads += 1 }

        for _ in 0..<5 { reloader.importFinished() }
        #expect(counter.reloads == 0)

        await waitFor { counter.reloads > 0 }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(counter.reloads == 1)
    }

    @Test("a reload due while paused waits and runs once when the pause lifts")
    func pauseHoldsTheReload() async {
        let counter = Counter()
        let reloader = RemoteImportReloader(delay: .milliseconds(30), sleep: Self.noWait) { counter.reloads += 1 }

        reloader.isPaused = true
        reloader.importFinished()
        await waitFor { reloader.hasHeldReload }
        #expect(reloader.hasHeldReload)
        #expect(counter.reloads == 0)

        reloader.isPaused = false
        #expect(counter.reloads == 1)
        #expect(!reloader.hasHeldReload)
        reloader.isPaused = true
        reloader.isPaused = false
        #expect(counter.reloads == 1)
    }

    @Test("lifting a pause with nothing due does not reload")
    func pauseWithoutImportIsQuiet() {
        let counter = Counter()
        let reloader = RemoteImportReloader(delay: .milliseconds(30)) { counter.reloads += 1 }

        reloader.isPaused = true
        reloader.isPaused = false

        #expect(counter.reloads == 0)
    }

    @Test("only a finished import event counts")
    func onlyFinishedImportsCount() {
        let unrelated = Notification(name: .init("Other"), userInfo: ["key": "value"])
        #expect(!RemoteImportReloader.isFinishedImport(unrelated, storeIdentifier: "store"))
        let empty = Notification(name: NSPersistentCloudKitContainer.eventChangedNotification)
        #expect(!RemoteImportReloader.isFinishedImport(empty, storeIdentifier: "store"))
    }

    // Assistant battery and heat check 2026-10-10, finding 4: a failed import
    // reloaded too.
    @Test("a finished import into the store that worked counts, as before")
    func successfulImportCounts() {
        #expect(RemoteImportReloader.isFinishedImport(
            type: .import, ended: true, succeeded: true, eventStore: "store", storeIdentifier: "store"
        ))
    }

    @Test("a failed, unfinished, other store's or export event doesn't count")
    func failedImportDoesNotCount() {
        func counts(
            _ type: NSPersistentCloudKitContainer.EventType = .import,
            ended: Bool = true,
            succeeded: Bool = true,
            store: String = "store"
        ) -> Bool {
            RemoteImportReloader.isFinishedImport(
                type: type, ended: ended, succeeded: succeeded, eventStore: store, storeIdentifier: "store"
            )
        }
        #expect(!counts(succeeded: false))
        #expect(!counts(ended: false))
        #expect(!counts(store: "other"))
        #expect(!counts(.export))
        #expect(!counts(.setup))
    }

    // Finding 4: every finished import reloaded in the background too.
    @Test("away, an import's reload is held, and the return drops it: the owner's own reload shows it")
    func awayHoldsAndReturnDrops() async {
        let counter = Counter()
        let reloader = RemoteImportReloader(delay: .milliseconds(30), sleep: Self.noWait) { counter.reloads += 1 }

        reloader.appLeft()
        reloader.importFinished()
        await waitFor { reloader.hasHeldReload }
        #expect(reloader.hasHeldReload)
        #expect(counter.reloads == 0)
        // A sheet closing while away doesn't run it either.
        reloader.isPaused = true
        reloader.isPaused = false
        #expect(counter.reloads == 0)

        reloader.appReturned()
        #expect(!reloader.hasHeldReload)
        #expect(counter.reloads == 0)
    }

    @Test("back on screen, imports reload as before")
    func returnedReloadsAgain() async {
        let counter = Counter()
        let reloader = RemoteImportReloader(delay: .milliseconds(30), sleep: Self.noWait) { counter.reloads += 1 }

        reloader.appLeft()
        reloader.appReturned()
        reloader.importFinished()
        await waitFor { counter.reloads > 0 }
        #expect(counter.reloads == 1)
        #expect(!reloader.hasHeldReload)
    }

    @Test("a reload still settling when the app comes back is dropped, not run after the return's own")
    func returnCancelsTheSettle() async {
        let counter = Counter()
        let cancelled = Flag()
        // Settles for a minute unless cancelled; a passing run never waits it out.
        let sleep: RemoteImportReloader.Sleep = { _ in
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                await cancelled.set()
                throw error
            }
        }
        let reloader = RemoteImportReloader(delay: .seconds(60), sleep: sleep) { counter.reloads += 1 }

        reloader.appLeft()
        reloader.importFinished()
        reloader.appReturned()
        await waitFor { cancelled.isSet }
        #expect(cancelled.isSet)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(counter.reloads == 0)
        #expect(!reloader.hasHeldReload)
    }
}

@MainActor
private final class Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}
