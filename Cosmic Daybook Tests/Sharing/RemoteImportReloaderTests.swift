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

    /// Waits for `condition`, up to two seconds; timing on a busy simulator
    /// varies, so no test depends on an exact interval.
    private func waitFor(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("a burst of imports reloads once, after it settles")
    func burstReloadsOnce() async {
        let counter = Counter()
        let reloader = RemoteImportReloader(delay: .milliseconds(30)) { counter.reloads += 1 }

        for _ in 0..<5 { reloader.importFinished() }
        #expect(counter.reloads == 0)

        await waitFor { counter.reloads > 0 }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(counter.reloads == 1)
    }

    @Test("a reload due while paused waits and runs once when the pause lifts")
    func pauseHoldsTheReload() async {
        let counter = Counter()
        let reloader = RemoteImportReloader(delay: .milliseconds(30)) { counter.reloads += 1 }

        reloader.isPaused = true
        reloader.importFinished()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(counter.reloads == 0)

        reloader.isPaused = false
        #expect(counter.reloads == 1)
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
}
