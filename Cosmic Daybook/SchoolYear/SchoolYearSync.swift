// SchoolYearSync.swift
// One school year on every device.
//
// The start month and day, and whether day counters start over on it, describe the class,
// not the device: the Mac, iPhone and iPad must agree on them, or a date that is "this year"
// on one is "last year" on another. They travel through iCloud key-value storage.
//
// UserDefaults stays the local copy every reader uses — `FloridaGradeCalculator`,
// `YearPlanStaleness`, `SchoolYearCounters` and MCP read it directly, off the main actor —
// and this type keeps it in step with iCloud:
//
// - At launch and on every change from iCloud, the iCloud values are copied into
//   UserDefaults, then `.schoolYearSettingsDidSync` tells `SchoolYearStore` to reload.
// - An explicit edit (Settings, the MCP tool, a backup restore) publishes all three values.
//   Nothing else does: a launch never publishes, so a device holding a stale or default
//   value can't overwrite the class's real one.
// - The one exception is the first moment: while iCloud holds no start date at all, the
//   Mac — the class's main device — publishes what it has. An iPhone or iPad only adopts.
// - Only values set on this device are ever published, never the defaults (Sept 1, counting
//   all history). A new or reinstalled Mac holds none, and at launch iCloud key-value storage
//   may not have downloaded yet, so it looks empty: publishing the defaults then would put
//   Sept 1 over the class's real start on every device.
//
// The live instance exists only in the running app (`start()` from app setup, never under
// unit tests): a Mac test run is signed into the guide's iCloud, and a test's start date
// must not reach their devices. Tests build their own instance around an in-memory store.

import Foundation
import OSLog

/// Where the synced school-year settings travel. The app's is iCloud key-value storage.
protocol SchoolYearCloudStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: SchoolYearCloudStore {}

extension Notification.Name {
    /// The synced school-year settings in UserDefaults changed underneath the app.
    static let schoolYearSettingsDidSync = Notification.Name("SchoolYearSettingsDidSync")
}

@MainActor
final class SchoolYearSync {
    /// The running app's instance; nil until `start()`, and always nil under unit tests.
    private(set) static var shared: SchoolYearSync?

    nonisolated static let monthKey = UserDefaultsKeys.schoolYearStartMonth
    nonisolated static let dayKey = UserDefaultsKeys.schoolYearStartDay
    nonisolated static let modeKey = UserDefaultsKeys.schoolYearCountersResetAtYearStart

    private static let logger = Logger(subsystem: "CosmicDaybook", category: "SchoolYearSync")

    let cloud: SchoolYearCloudStore
    let defaults: UserDefaults
    /// Whether this device may fill an empty iCloud with its own values (the Mac only).
    let seedsEmptyCloud: Bool
    private var observation: Task<Void, Never>?

    init(cloud: SchoolYearCloudStore, defaults: UserDefaults, seedsEmptyCloud: Bool) {
        self.cloud = cloud
        self.defaults = defaults
        self.seedsEmptyCloud = seedsEmptyCloud
    }

    /// Starts the app's instance: pulls the latest values, adopts or seeds, then follows iCloud.
    static func start() {
        guard shared == nil, !AppBootstrapping.isRunningUnitTests else { return }
        #if os(macOS)
        let seeds = true
        #else
        let seeds = false
        #endif
        let sync = SchoolYearSync(cloud: NSUbiquitousKeyValueStore.default, defaults: .standard, seedsEmptyCloud: seeds)
        shared = sync
        sync.cloud.synchronize()
        sync.adoptOrSeed()
        sync.observeCloud()
    }

    // MARK: - Launch

    /// What a launch did with the settings.
    enum LaunchOutcome: Equatable {
        /// iCloud's values were copied into UserDefaults (`changed`: they differed).
        case adopted(changed: Bool)
        /// iCloud was empty and this Mac filled it.
        case seeded
        /// iCloud was empty and this device doesn't seed; the local values stand for now.
        case waiting
    }

    /// Copies iCloud's values into UserDefaults; when iCloud has no start date yet, the Mac
    /// publishes its own, if it has one. Never publishes over a value iCloud already holds.
    @discardableResult
    func adoptOrSeed() -> LaunchOutcome {
        if Self.cloudStart(in: cloud) != nil {
            let changed = adoptFromCloud()
            if cloud.object(forKey: Self.modeKey) as? Bool == nil, seedsEmptyCloud, Self.hasLocalMode(in: defaults) {
                // A start date without the mode: add this Mac's mode, leave the date alone.
                cloud.set(SchoolYearCounters.isResetting(in: defaults), forKey: Self.modeKey)
                cloud.synchronize()
            }
            return .adopted(changed: changed)
        }
        guard seedsEmptyCloud, Self.localStart(in: defaults) != nil else { return .waiting }
        publishLocalSettings()
        Self.logger.info("Seeded iCloud with this Mac's school-year settings")
        return .seeded
    }

    /// Copies whatever valid values iCloud holds into UserDefaults. Returns true when anything
    /// changed, after telling the app so.
    @discardableResult
    func adoptFromCloud() -> Bool {
        var changed = false
        if let (month, day) = Self.cloudStart(in: cloud) {
            if defaults.object(forKey: Self.monthKey) as? Int != month {
                defaults.set(month, forKey: Self.monthKey)
                changed = true
            }
            if defaults.object(forKey: Self.dayKey) as? Int != day {
                defaults.set(day, forKey: Self.dayKey)
                changed = true
            }
        }
        if let mode = cloud.object(forKey: Self.modeKey) as? Bool,
           defaults.object(forKey: Self.modeKey) as? Bool != mode {
            defaults.set(mode, forKey: Self.modeKey)
            changed = true
        }
        if changed {
            YearPlanStaleness.invalidateCache()
            Self.logger.info("Adopted the school-year settings from iCloud")
            NotificationCenter.default.post(name: .schoolYearSettingsDidSync, object: nil)
        }
        return changed
    }

    // MARK: - Publishing

    /// Publishes the given settings. Called for explicit edits only.
    func publish(month: Int, day: Int, resetting: Bool) {
        cloud.set(month, forKey: Self.monthKey)
        cloud.set(day, forKey: Self.dayKey)
        cloud.set(resetting, forKey: Self.modeKey)
        cloud.synchronize()
    }

    /// Publishes what UserDefaults holds now (after a restore wrote it, or to seed): only the
    /// values set here, never a default standing in for one.
    func publishLocalSettings() {
        let start = Self.localStart(in: defaults)
        if let start {
            cloud.set(start.month, forKey: Self.monthKey)
            cloud.set(start.day, forKey: Self.dayKey)
        }
        if Self.hasLocalMode(in: defaults) {
            cloud.set(SchoolYearCounters.isResetting(in: defaults), forKey: Self.modeKey)
        }
        cloud.synchronize()
    }

    /// A backup restore rewrote the settings in UserDefaults: publish them, and reload the app.
    func localSettingsReplaced() {
        publishLocalSettings()
        YearPlanStaleness.invalidateCache()
        NotificationCenter.default.post(name: .schoolYearSettingsDidSync, object: nil)
    }

    // MARK: - Following iCloud

    private func observeCloud() {
        guard observation == nil else { return }
        observation = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
                .map { _ in () }
            for await _ in changes {
                self?.adoptFromCloud()
            }
        }
    }

    // MARK: - Values

    /// iCloud's start date, when it holds a valid one.
    static func cloudStart(in cloud: SchoolYearCloudStore) -> (month: Int, day: Int)? {
        guard let month = (cloud.object(forKey: monthKey) as? NSNumber)?.intValue, (1...12).contains(month),
              let day = (cloud.object(forKey: dayKey) as? NSNumber)?.intValue, (1...31).contains(day)
        else { return nil }
        return (month, day)
    }

    /// The start date set on this device, when one is: nil means only the default stands.
    nonisolated static func localStart(in defaults: UserDefaults) -> (month: Int, day: Int)? {
        guard let month = defaults.object(forKey: monthKey) as? Int, (1...12).contains(month),
              let day = defaults.object(forKey: dayKey) as? Int, (1...31).contains(day)
        else { return nil }
        return (month, day)
    }

    /// Whether the counter mode was set on this device (or by the old epoch it replaced).
    nonisolated static func hasLocalMode(in defaults: UserDefaults) -> Bool {
        SchoolYearCounters.hasExplicitMode(in: defaults)
            || defaults.object(forKey: UserDefaultsKeys.schoolYearCounterEpoch) != nil
    }

    /// The start date as UserDefaults resolves it, defaulted as `SchoolYearStore` does.
    nonisolated static func resolvedStart(in defaults: UserDefaults) -> (month: Int, day: Int) {
        let month = defaults.object(forKey: monthKey) as? Int
        let day = defaults.object(forKey: dayKey) as? Int
        return (
            month.flatMap { (1...12).contains($0) ? $0 : nil } ?? 9,
            day.flatMap { (1...31).contains($0) ? $0 : nil } ?? 1
        )
    }
}
