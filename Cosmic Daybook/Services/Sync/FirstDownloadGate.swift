import Foundation
import OSLog

/// Holds classroom maintenance back while the private store downloads from
/// iCloud for the first time — after Reset Local Cache, or on a new device.
///
/// CloudKit fills an empty store zone by zone, and a zone's rows can land
/// before its CKShare record does. Until that share arrives,
/// `fetchShares(matching:)` says the rows belong to no share, so zone repair
/// took them for orphans and moved them into the classroom share. On
/// 2026-09-28 it did that to 4,003 records in the half hour after a reset;
/// earlier resets are how classroom data came to be scattered across zones.
/// Default templates seeded into the empty store likewise duplicated the ones
/// still on their way down.
///
/// The gate is armed when `CoreDataStack` loads without a private store file
/// and CloudKit on, and it opens on the first import event for the private
/// store that finishes successfully — an import event ends only once
/// everything it fetched is in the store. It is persisted, so a relaunch
/// mid-download stays held. While it is armed: zone repair (automatic and
/// manual) and the orphan guard do nothing, and the template seeder waits.
nonisolated enum FirstDownloadGate {

    static let key = UserDefaultsKeys.firstDownloadPending

    private static let logger = Logger.sync

    /// True while the first download into a fresh private store is still under way.
    static func isPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    /// Holds maintenance back until the private store's first import finishes.
    static func arm(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
        logger.notice("First download from iCloud pending: zone repair and template seeding wait for it")
    }

    /// Lets maintenance run again. Returns whether the gate was armed, so the
    /// caller runs what it held back exactly once.
    @discardableResult
    static func open(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: key) else { return false }
        defaults.removeObject(forKey: key)
        return true
    }
}
