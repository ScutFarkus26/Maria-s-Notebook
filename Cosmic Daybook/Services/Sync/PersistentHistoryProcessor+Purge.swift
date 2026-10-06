import Foundation
@preconcurrency import CoreData
import OSLog

// MARK: - Purging old history, one store at a time
//
// Each store's history is purged only behind that store's own last successful
// export. One date for both stores (until 2026-10-05) moved with whichever
// store exported last, so the classroom share's export could clear history the
// notebook's mirroring delegate hadn't exported yet (hunt #29). A start dated
// in the future (a clock that ran ahead) is never taken: it would put the gate
// past everything.

extension PersistentHistoryProcessor {

    /// How old a transaction must be before it is eligible for purging.
    /// Apple: "long enough for the history to become irrelevant, which can be
    /// several months for apps that people use on a regular basis."
    static let purgeRetention: TimeInterval = 180 * 24 * 3600

    /// Minimum interval between purges. Apple: "Apps generally only need to
    /// purge the history several times a year."
    static let purgeInterval: TimeInterval = 60 * 24 * 3600

    /// Purge persistent history following Apple's documented pattern for
    /// CloudKit-backed stores ("Sharing Core Data objects between iCloud
    /// users"): delete only transactions that predate BOTH the start of the
    /// store's last successful `.export` event AND a several-month retention
    /// window, each store on its own (`affectedStores`).
    ///
    /// `NSCloudKitMirroringDelegate` keeps its own history cursor that this
    /// process cannot read. Purging transactions it hasn't exported yet
    /// invalidates that cursor and forces a full reset against the CloudKit
    /// server — and any deletion whose only record was the purged tombstone
    /// resurrects on the next import. The export-date gate guarantees the
    /// delegate consumed everything we delete; the retention window keeps the
    /// history available for other consumers (BackupChangeTracker) and for
    /// devices that re-enable sync after running in the degraded local mode.
    func purgeOldHistory(now: Date = Date()) async {
        // Never purge a store before CloudKit has demonstrably exported it. On
        // stores that have never synced this keeps all history for a future
        // first export; disk cost is acceptable at this app's write volume.
        let starts = Self.exportStarts(in: defaults).filter { $0.value <= now }
        guard !starts.isEmpty else {
            Self.logger.debug("Skipping history purge — no successful CloudKit export recorded")
            return
        }

        if let lastPurge = defaults.object(
            forKey: UserDefaultsKeys.persistentHistoryLastPurgeDate
        ) as? TimeInterval,
           now.timeIntervalSince1970 - lastPurge < Self.purgeInterval {
            return
        }

        let retentionCutoff = now.addingTimeInterval(-Self.purgeRetention)
        let cutoffs = starts.mapValues { min($0, retentionCutoff) }

        let context = container.newBackgroundContext()
        let purged: Bool = await context.perform {
            var purgedAny = false
            for store in context.persistentStoreCoordinator?.persistentStores ?? [] {
                guard let cutoff = cutoffs[store.identifier] else { continue }
                let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff)
                purgeRequest.affectedStores = [store]
                do {
                    try context.execute(purgeRequest)
                    purgedAny = true
                    let name: String = store.configurationName
                    Self.logger.info("Purged \(name, privacy: .public) history before \(cutoff, privacy: .public)")
                } catch {
                    Self.logger.error("Failed to purge history: \(error.localizedDescription)")
                }
            }
            return purgedAny
        }

        if purged {
            defaults.set(now.timeIntervalSince1970, forKey: UserDefaultsKeys.persistentHistoryLastPurgeDate)
        }
    }

    // MARK: - Export starts per store

    /// Notes that an export of the store with `storeIdentifier`, begun at
    /// `start`, finished successfully: the mirroring delegate has consumed every
    /// transaction of that store before `start`. Only moves forward, but a start
    /// left in the future by a clock that ran ahead is replaced; a future start
    /// itself is never kept. `liveStoreIdentifiers`, when given, are the stores
    /// the app has open: entries for any other (one a reset replaced) go.
    nonisolated static func recordExportStart(
        _ start: Date,
        storeIdentifier: String?,
        liveStoreIdentifiers: Set<String>? = nil,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        guard let storeIdentifier, start <= now else { return }
        var starts = defaults.dictionary(forKey: UserDefaultsKeys.cloudKitLastSuccessfulExportStartByStore)
            as? [String: TimeInterval] ?? [:]
        if let live = liveStoreIdentifiers {
            starts = starts.filter { live.contains($0.key) }
        }
        if let previous = starts[storeIdentifier].map(Date.init(timeIntervalSince1970:)),
           previous <= now, previous >= start { return }
        starts[storeIdentifier] = start.timeIntervalSince1970
        defaults.set(starts, forKey: UserDefaultsKeys.cloudKitLastSuccessfulExportStartByStore)
    }

    /// Each store's last successful export start, by store identifier.
    nonisolated static func exportStarts(in defaults: UserDefaults) -> [String: Date] {
        let stored = defaults.dictionary(forKey: UserDefaultsKeys.cloudKitLastSuccessfulExportStartByStore)
            as? [String: TimeInterval] ?? [:]
        return stored.mapValues(Date.init(timeIntervalSince1970:))
    }
}
