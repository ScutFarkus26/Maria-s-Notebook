// ScheduledBackupTiming.swift
// When the next interval backup is due.
//
// Pure, so the Mac's NSBackgroundActivityScheduler (armed with it before
// every backup) computes exactly the wait the interval loop has always
// slept for, and tests can pin it on iOS.

import Foundation

nonisolated enum ScheduledBackupTiming {
    /// Seconds until the next interval backup: one interval after the last
    /// one, or a full interval from `now` when none has run yet; zero once
    /// it is due. The interval loop's formula.
    static func delay(intervalHours: Int, lastBackup: Date?, now: Date) -> TimeInterval {
        let interval = TimeInterval(intervalHours * 3600)
        let next = (lastBackup ?? now).addingTimeInterval(interval)
        return max(0, next.timeIntervalSince(now))
    }

    /// The wait before the next interval backup, or nil when interval backups
    /// are off (the switch is off or the interval isn't positive): the check
    /// `startScheduledBackups` makes at launch, made again after every run
    /// before the Mac re-arms.
    static func nextDelay(enabled: Bool, intervalHours: Int, lastBackup: Date?, now: Date) -> TimeInterval? {
        guard enabled, intervalHours > 0 else { return nil }
        return delay(intervalHours: intervalHours, lastBackup: lastBackup, now: now)
    }

    /// The shortest wait the Mac arms its activity with. An overdue backup's
    /// wait is zero, and NSBackgroundActivityScheduler raises for an interval
    /// under one second — an exception thrown while launch finishes, which
    /// crashed the Mac app on every launch once a backup was overdue (it
    /// never ran, so it stayed overdue). A minute also keeps the backup out
    /// of launch itself.
    static let minimumSchedulerInterval: TimeInterval = 60

    /// The interval the Mac arms its activity with for a wait of `delay`.
    static func schedulerInterval(forDelay delay: TimeInterval) -> TimeInterval {
        max(delay, minimumSchedulerInterval)
    }

    /// How far either side of the due time the Mac's scheduler may move a
    /// backup: a tenth of the wait. NSBackgroundActivityScheduler's default
    /// is half, which could shift a 4-hour backup by two hours.
    static func tolerance(forDelay delay: TimeInterval) -> TimeInterval {
        delay / 10
    }
}
