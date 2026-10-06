import Foundation
import Testing
@testable import CosmicDaybook

// Review of the 2026-10-05 fixes: the launch counted the notebook as caught up
// with iCloud whenever CloudKit wasn't active, which is also the case when sync
// is on but CloudKit failed to start that launch. The orphan graces then acted
// on rows still on their way down.
@Suite("Launch grace wiring")
struct LaunchGraceWiringTests {

    @Test("With sync on, nothing counts as caught up without an import, whatever CloudKit did")
    func syncOnWaitsForAnImport() {
        #expect(AppBootstrapper.caughtUpWithoutImports(syncPreferred: true) == nil)
    }

    @Test("With sync turned off, the notebook is caught up now")
    func syncOffIsCaughtUp() {
        let now = Date(timeIntervalSinceReferenceDate: 780_000_000)
        #expect(AppBootstrapper.caughtUpWithoutImports(syncPreferred: false, now: now) == now)
    }
}
