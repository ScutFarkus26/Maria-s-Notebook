import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

/// The album search lets go of its language model a few minutes after the
/// last search. The countdown behind that: every touch pushes the deadline
/// back, and the action runs once a whole interval passes with no touch. On a
/// clock the test moves, so the timing is exact and nothing waits minutes.
@Suite("Idle countdown")
@MainActor
struct IdleCountdownTests {

    /// Counts the countdown's firings; its action runs off the main actor.
    private nonisolated final class FireCounter: Sendable {
        private let fired = Mutex(0)
        func fire() { fired.withLock { $0 += 1 } }
        var count: Int { fired.withLock { $0 } }
    }

    private static func at(_ seconds: Int) -> ManualTestClock.Instant {
        ManualTestClock.Instant(offset: .seconds(seconds))
    }

    @Test("It fires once a whole interval passes with no touch, and not before")
    func firesAfterTheInterval() async {
        let clock = ManualTestClock()
        let fired = FireCounter()
        let countdown = IdleCountdown(interval: .seconds(300), clock: clock) { fired.fire() }

        countdown.touch()
        #expect(countdown.deadline == Self.at(300))
        #expect(await AlbumTestSupport.waitUntil { clock.pendingDeadlines == [Self.at(300)] })
        clock.advance(by: .seconds(299))
        #expect(fired.count == 0)
        clock.advance(by: .seconds(1))
        #expect(await AlbumTestSupport.waitUntil { fired.count == 1 })
        #expect(countdown.deadline == nil)
    }

    @Test("Touches that keep coming keep it from firing")
    func touchesPushItBack() async {
        let clock = ManualTestClock()
        let fired = FireCounter()
        let countdown = IdleCountdown(interval: .seconds(300), clock: clock) { fired.fire() }

        // A search every four minutes for most of an hour.
        countdown.touch()
        for _ in 1...12 {
            clock.advance(by: .seconds(240))
            countdown.touch()
        }
        // Time never reached the deadline, so nothing can have fired. (The
        // countdown may still be asleep on an earlier deadline; waking there,
        // it sleeps again until this one.)
        #expect(countdown.deadline == Self.at(12 * 240 + 300))
        #expect(fired.count == 0)

        // Then the searches stop.
        clock.advance(by: .seconds(300))
        #expect(await AlbumTestSupport.waitUntil { fired.count == 1 })
    }

    @Test("A touch after it fired starts a fresh countdown")
    func restartsAfterFiring() async {
        let clock = ManualTestClock()
        let fired = FireCounter()
        let countdown = IdleCountdown(interval: .seconds(300), clock: clock) { fired.fire() }

        countdown.touch()
        clock.advance(by: .seconds(300))
        #expect(await AlbumTestSupport.waitUntil { fired.count == 1 })

        countdown.touch()
        #expect(countdown.deadline == Self.at(600))
        clock.advance(by: .seconds(300))
        #expect(await AlbumTestSupport.waitUntil { fired.count == 2 })
    }
}
