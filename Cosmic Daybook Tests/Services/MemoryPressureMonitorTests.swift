import Foundation
import Testing
#if os(iOS)
import UIKit
#endif
@testable import CosmicDaybook

// MARK: - What reaches the memory-pressure handler
//
// Two sources feed `MemoryPressureMonitor`: the dispatch memory-pressure
// source, and on iOS UIKit's memory warning, which takes the same warning
// path — same 30-second throttle, same handler, so the same caches clear —
// and a warning that arrives both ways inside one window clears them once.
// The UIKit path is driven by posting its notification to a private center
// with a hand-advanced clock; a dispatch event can't be raised from a test,
// so its mapping to a level is checked directly.

@Suite("Memory pressure monitor")
@MainActor
struct MemoryPressureMonitorTests {
    /// The throttle's clock, advanced by hand.
    private final class ManualClock {
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    }

    /// The levels that reached the pressure handler, in order.
    private final class HandlerLog {
        var levels: [MemoryPressureLevel] = []
    }

    @Test("A dispatch event maps to the level of the same name, and nothing else maps")
    func dispatchEventMapping() {
        #expect(MemoryPressureMonitor.level(for: .warning) == .warning)
        #expect(MemoryPressureMonitor.level(for: .critical) == .critical)
        #expect(MemoryPressureMonitor.level(for: .normal) == nil)
    }

    #if os(iOS)
    private static func postMemoryWarning(to center: NotificationCenter) {
        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
    }

    @Test("UIKit's memory warning reaches the warning handler once per throttle window")
    func uikitWarningIsThrottled() {
        let center = NotificationCenter()
        let clock = ManualClock()
        let log = HandlerLog()
        let monitor = MemoryPressureMonitor(notificationCenter: center, now: { clock.now })
        monitor.startMonitoring { log.levels.append($0) }
        defer { monitor.stopMonitoring() }

        Self.postMemoryWarning(to: center)
        #expect(log.levels == [.warning])
        #expect(monitor.lastPressureLevel == .warning)
        #expect(monitor.pressureEventCount == 1)

        clock.now += 29
        Self.postMemoryWarning(to: center)
        #expect(log.levels == [.warning], "a second warning inside the 30 s window is throttled")

        clock.now += 1
        Self.postMemoryWarning(to: center)
        #expect(log.levels == [.warning, .warning], "the next window responds again")
        #expect(monitor.pressureEventCount == 2)
    }

    @Test("A stopped monitor no longer hears UIKit's memory warning")
    func stoppedMonitorIgnoresUIKitWarning() {
        let center = NotificationCenter()
        let log = HandlerLog()
        let monitor = MemoryPressureMonitor(notificationCenter: center)
        monitor.startMonitoring { log.levels.append($0) }
        monitor.stopMonitoring()

        Self.postMemoryWarning(to: center)
        #expect(log.levels.isEmpty)
        #expect(monitor.pressureEventCount == 0)
    }
    #endif
}
