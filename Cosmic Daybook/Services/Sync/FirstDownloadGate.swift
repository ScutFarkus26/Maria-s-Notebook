import CloudKit
import Foundation
import OSLog
import Synchronization

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
/// everything it fetched is in the store — or straight away when no iCloud
/// account is signed in, since then nothing will download. It is persisted, so
/// a relaunch mid-download stays held. While it is armed: zone repair
/// (automatic and manual) and the orphan guard do nothing, and the template
/// seeder waits.
nonisolated enum FirstDownloadGate {

    static let key = UserDefaultsKeys.firstDownloadPending

    private static let logger = Logger.sync

    /// True while the first download into a fresh private store is still under way.
    static func isPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key) && !liftedForSession.withLock { $0 }
    }

    private static let liftedForSession = Mutex(false)

    /// Lets maintenance run for the rest of this session while the gate itself
    /// stays armed: no iCloud account is signed in, so nothing will download
    /// now. Opening the gate for good on that answer left the whole download
    /// unguarded once the account signed in, or when the answer was only
    /// momentary at login (2026-10-05 review); the next launch asks again.
    static func liftForSession() {
        liftedForSession.withLock { $0 = true }
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

    /// Whether nothing will ever download into the fresh store: iCloud sync is
    /// on (`cloudKitActive`) but no iCloud account is signed in. The gate
    /// opens then, rather than hold maintenance back for good.
    static func nothingWillDownload(accountStatus: CKAccountStatus, cloudKitActive: Bool) -> Bool {
        cloudKitActive && accountStatus == .noAccount
    }
}
