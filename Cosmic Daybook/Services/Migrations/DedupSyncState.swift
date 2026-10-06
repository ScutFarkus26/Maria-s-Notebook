import CloudKit
import CoreData
import Foundation
import os

/// What this device can see of the iCloud records behind a group of duplicates, which decides
/// whether the cleanup may delete any of them (bug hunt 2026-10-05, #20).
///
/// Every device runs the cleanup on its own, so it deletes only when every device would keep the
/// same copy. Two cases where that can't be known:
/// - **Sync off.** The stores open without CloudKit, and Core Data then reports no record for any
///   row (`recordID(for:)` is nil; checked on macOS 27.0), so the tie-break falls to the object
///   URI, which no other device shares, and the deletes go up when sync comes back. The cleanup
///   doesn't run at all.
/// - **No copy sent yet.** In a synced notebook, a group none of whose copies has reached iCloud
///   waits for a later pass.
///
/// Without a container (the tests' default) nothing is looked up and the cleanup runs as before.
nonisolated enum DedupSyncState {
    private static let logger = Logger(subsystem: "CosmicDaybook", category: "Dedup")

    /// Test seam: a row's CloudKit record name, instead of asking the container.
    @TaskLocal static var recordNameOverride: (@Sendable (NSManagedObjectID) -> String?)?

    /// Test seam: whether the notebook syncs with iCloud, instead of reading its store descriptions.
    @TaskLocal static var syncsOverride: Bool?

    /// The CloudKit record name behind `objectID`, the same on every device that has the record;
    /// nil before the row has reached iCloud, and for every row while sync is off.
    static func recordName(of objectID: NSManagedObjectID, container: NSPersistentCloudKitContainer?) -> String? {
        if let recordNameOverride { return recordNameOverride(objectID) }
        return container?.recordID(for: objectID)?.recordName
    }

    /// Whether the cleanup may run against `container`'s notebook: not when its stores were
    /// opened without iCloud. With no container there is nothing to ask, and it may.
    static func mayDeduplicate(container: NSPersistentCloudKitContainer?) -> Bool {
        if let syncsOverride { return syncsOverride }
        guard let container else { return true }
        return container.persistentStoreDescriptions.contains { $0.cloudKitContainerOptions != nil }
    }

    // MARK: - Settling

    /// How long one child's copies of a day must sit unchanged before the cleanup folds them.
    static let settleInterval: TimeInterval = 10 * 60

    /// Test seam: when the store with this identifier last finished an import (its start),
    /// instead of reading `ImportWatermark`.
    @TaskLocal static var lastImportOverride: (@Sendable (String) -> Date?)?

    /// True while copies of one attendance day may still be changing where this device can't
    /// see: one changed in the last `settleInterval`, or no import that began after the newest
    /// change has finished into their store. Folding copies the winning mark onto the kept copy
    /// and sends it to iCloud; done from a view that hasn't caught up, it could overwrite a newer
    /// mark made on another device (2026-10-05 review). The grid reads the winner across copies
    /// meanwhile, so waiting shows nothing wrong. Without a container (the tests' default)
    /// nothing is looked up and the cleanup folds at once.
    static func stillSettling(
        _ records: [CDAttendanceRecord],
        container: NSPersistentCloudKitContainer?,
        now: Date = Date()
    ) -> Bool {
        guard container != nil || lastImportOverride != nil else { return false }
        let newest = records.compactMap(\.modifiedAt).max() ?? .distantPast
        if now.timeIntervalSince(newest) < settleInterval { return true }
        let stores = Set(records.compactMap { $0.objectID.persistentStore?.identifier })
        for store in stores {
            let lastImport = lastImportOverride.map { $0(store) }
                ?? ImportWatermark.lastImport(intoStoreWithIdentifier: store, now: now)
            guard let lastImport, lastImport > newest else { return true }
        }
        return false
    }

    // MARK: - Tied copies of one id

    /// Test seam: when a row's CloudKit record last changed in iCloud, instead of asking the
    /// container.
    @TaskLocal static var recordChangedOverride: (@Sendable (NSManagedObjectID) -> Date?)?

    /// When the CloudKit record behind `objectID` last changed in iCloud (the server's time, the
    /// same on every device); nil before the row has reached iCloud.
    static func recordChanged(of objectID: NSManagedObjectID, container: NSPersistentCloudKitContainer?) -> Date? {
        if let recordChangedOverride { return recordChangedOverride(objectID) }
        return container?.record(for: objectID)?.modificationDate
    }

    /// True while copies of one id whose `createdAt` ties can't yet be folded safely. Their keeper
    /// then falls to the record name, and mid-way through a Replace restore on another device
    /// (the old copies' deletes and the restored copies not all here yet) that can keep the
    /// outgoing copy and delete the incoming one; both deletes sync and the record is gone
    /// (2026-10-05 hunt). So the group waits while:
    /// - any copy has no record in iCloud yet, or
    /// - a copy changed in iCloud within `settleInterval`, or no import that began after that
    ///   change has finished into its store: the rest of the restore may still be on its way.
    /// The keeper rule itself is unchanged and the same on every device; only when it runs
    /// waits, and waiting deletes nothing. Without a container (the tests' default) nothing is
    /// looked up and the group folds at once.
    static func tieStillSettling(
        _ objects: [NSManagedObject],
        container: NSPersistentCloudKitContainer?,
        now: Date = Date()
    ) -> Bool {
        guard container != nil || recordNameOverride != nil else { return false }
        let entity = objects.first?.entity.name ?? "record"
        if objects.contains(where: { recordName(of: $0.objectID, container: container) == nil }) {
            logger.info("Left \(objects.count) tied copies of one \(entity, privacy: .public): one isn't in iCloud yet")
            return true
        }
        guard let newest = objects.compactMap({ recordChanged(of: $0.objectID, container: container) }).max() else {
            return false
        }
        var settling = now.timeIntervalSince(newest) < settleInterval
        if !settling {
            let stores = Set(objects.compactMap { $0.objectID.persistentStore?.identifier })
            settling = stores.contains { store in
                let lastImport = lastImportOverride.map { $0(store) }
                    ?? ImportWatermark.lastImport(intoStoreWithIdentifier: store, now: now)
                guard let lastImport else { return true }
                return lastImport <= newest
            }
        }
        if settling {
            logger.info("Left \(objects.count) tied copies of one \(entity, privacy: .public): one changed lately")
        }
        return settling
    }

    /// True when none of `objects` (copies of one record) has reached iCloud yet, so the group is
    /// left for a pass after they have.
    static func noCopySent(_ objects: [NSManagedObject], container: NSPersistentCloudKitContainer?) -> Bool {
        guard container != nil || recordNameOverride != nil else { return false }
        guard objects.allSatisfy({ recordName(of: $0.objectID, container: container) == nil }) else { return false }
        let entity = objects.first?.entity.name ?? "record"
        logger.info("Left \(objects.count) copies of one \(entity, privacy: .public) for later: none is in iCloud yet")
        return true
    }
}
