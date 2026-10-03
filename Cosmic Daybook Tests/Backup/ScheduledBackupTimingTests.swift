import Foundation
import Testing
@testable import CosmicDaybook

// The wait before the next interval backup. The iOS loop sleeps for it; the
// Mac arms a one-shot NSBackgroundActivityScheduler activity with it before
// every backup, allowing a tenth of it either side, and re-arms after each
// run only while the switch is on and the interval positive. The Mac's
// schedule must not move now that it no longer sleeps on the main actor, so
// the formula is pinned against the loop's own.
@Suite("Scheduled backup timing")
struct ScheduledBackupTimingTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let hour: TimeInterval = 3600

    /// The loop's inline computation in `AutoBackupManager.startScheduledBackups`.
    private static func loopWait(intervalHours: Int, lastBackup: Date?, now: Date) -> TimeInterval {
        let intervalSeconds = TimeInterval(intervalHours * 3600)
        let nextBackupTime = lastBackup?.addingTimeInterval(intervalSeconds) ?? now.addingTimeInterval(intervalSeconds)
        return max(0, nextBackupTime.timeIntervalSince(now))
    }

    @Test("With no backup yet, the first one is a full interval away")
    func firstBackupWaitsOneInterval() {
        let wait = ScheduledBackupTiming.delay(intervalHours: 4, lastBackup: nil, now: Self.now)
        let fourHours = 4 * Self.hour
        #expect(wait == fourHours)
    }

    @Test("After a backup, the next one is due one interval after it")
    func nextBackupCountsFromTheLastOne() {
        let lastBackup = Self.now.addingTimeInterval(-Self.hour)
        let wait = ScheduledBackupTiming.delay(intervalHours: 4, lastBackup: lastBackup, now: Self.now)
        let threeHours = 3 * Self.hour
        #expect(wait == threeHours)
    }

    @Test("An overdue backup is due now, never in the past")
    func overdueBackupIsDueNow() {
        let lastBackup = Self.now.addingTimeInterval(-10 * Self.hour)
        #expect(ScheduledBackupTiming.delay(intervalHours: 4, lastBackup: lastBackup, now: Self.now) == 0)
    }

    @Test("Same wait as the loop for every interval and clock offset")
    func matchesTheLoop() {
        for hours in [1, 2, 4, 8, 24] {
            #expect(
                ScheduledBackupTiming.delay(intervalHours: hours, lastBackup: nil, now: Self.now)
                    == Self.loopWait(intervalHours: hours, lastBackup: nil, now: Self.now)
            )
            for offset in stride(from: -30.0, through: 30.0, by: 2.5) {
                let lastBackup = Self.now.addingTimeInterval(offset * Self.hour)
                let wait = ScheduledBackupTiming.delay(intervalHours: hours, lastBackup: lastBackup, now: Self.now)
                let expected = Self.loopWait(intervalHours: hours, lastBackup: lastBackup, now: Self.now)
                #expect(wait == expected, "interval \(hours) h, last backup \(offset) h from now")
            }
        }
    }

    @Test("The Mac's window is a tenth of the wait either side, not the default half")
    func toleranceIsATenth() {
        let fourHourWindow = ScheduledBackupTiming.tolerance(forDelay: 4 * Self.hour)
        let threeHourWindow = ScheduledBackupTiming.tolerance(forDelay: 3 * Self.hour)
        let twentyFourMinutes: TimeInterval = 1440
        let eighteenMinutes: TimeInterval = 1080
        #expect(fourHourWindow == twentyFourMinutes)
        #expect(threeHourWindow == eighteenMinutes)
        #expect(ScheduledBackupTiming.tolerance(forDelay: 0) == 0)
    }

    @Test("The Mac never arms its scheduler with less than a minute, so an overdue backup can't crash launch")
    func schedulerIntervalHasAFloor() {
        // NSBackgroundActivityScheduler raises for an interval under 1 s.
        let minute: TimeInterval = 60
        let fourHours = 4 * Self.hour
        #expect(ScheduledBackupTiming.schedulerInterval(forDelay: 0) == minute)
        #expect(ScheduledBackupTiming.schedulerInterval(forDelay: 0.5) == minute)
        #expect(ScheduledBackupTiming.schedulerInterval(forDelay: fourHours) == fourHours)
        let overdue = ScheduledBackupTiming.delay(
            intervalHours: 4, lastBackup: Self.now.addingTimeInterval(-10 * Self.hour), now: Self.now
        )
        #expect(ScheduledBackupTiming.schedulerInterval(forDelay: overdue) >= 1)
    }

    @Test("Re-arming: nothing once switched off or the interval isn't positive, else the same wait")
    func nextDelayFollowsTheSwitchAndInterval() {
        let lastBackup = Self.now.addingTimeInterval(-Self.hour)
        func next(_ enabled: Bool, _ hours: Int) -> TimeInterval? {
            ScheduledBackupTiming.nextDelay(
                enabled: enabled, intervalHours: hours, lastBackup: lastBackup, now: Self.now
            )
        }
        let threeHours = 3 * Self.hour
        #expect(next(false, 4) == nil)
        #expect(next(true, 0) == nil)
        #expect(next(true, -2) == nil)
        #expect(next(true, 4) == threeHours)
        #expect(next(true, 1) == 0)
    }
}
