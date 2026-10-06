import CoreData
import Foundation

/// When each store last took in a CloudKit import that finished successfully,
/// for repairs that must not delete what may still be downloading: a row whose
/// parent is missing waits until an import that began after it was first seen
/// missing has finished (2026-10-05 hunt, #22). Apple has no "caught up" API;
/// its own example waits for an `.import` event with the store's identifier and
/// an end date (WWDC22 10119), which is what records one here
/// (`CloudKitSyncStatusService.handleCloudKitEvent`).
///
/// What is kept is the import's *start*: everything the server held before that
/// moment is in the store once the import has finished. Its end would let an
/// import that began before a row went missing count as coming after it.
///
/// Kept per store, by `NSPersistentStore.identifier`, so a store rebuilt by
/// Reset Local Cache (new files, a new identifier) has no import until its own
/// first one. A start later than now (a clock that ran ahead) is never taken:
/// it would read as an import after anything.
nonisolated enum ImportWatermark {

    private static var key: String { UserDefaultsKeys.cloudKitLastSuccessfulImportStartByStore }

    /// Notes that an import into the store with `storeIdentifier`, begun at
    /// `start`, finished successfully. Only moves forward, but a start left in
    /// the future by a clock that ran ahead is replaced. `liveStoreIdentifiers`,
    /// when given, are the stores the app has open: entries for any other (a
    /// store a reset replaced) are dropped.
    static func record(
        importStartedAt start: Date,
        storeIdentifier: String?,
        liveStoreIdentifiers: Set<String>? = nil,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        guard let storeIdentifier, start <= now else { return }
        var starts = stored(in: defaults)
        if let live = liveStoreIdentifiers {
            starts = starts.filter { live.contains($0.key) }
        }
        let previous = starts[storeIdentifier].map(Date.init(timeIntervalSinceReferenceDate:))
        if let previous, previous <= now, previous >= start { return }
        starts[storeIdentifier] = start.timeIntervalSinceReferenceDate
        defaults.set(starts, forKey: key)
    }

    /// When the last successful import into the store with `storeIdentifier`
    /// began, or nil when none is known (none since the store was made, or only
    /// one dated in the future).
    static func lastImport(
        intoStoreWithIdentifier storeIdentifier: String,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Date? {
        guard let start = stored(in: defaults)[storeIdentifier].map(Date.init(timeIntervalSinceReferenceDate:)),
              start <= now else { return nil }
        return start
    }

    /// `lastImport(intoStoreWithIdentifier:)` for one of `stack`'s stores: the
    /// notebook (private) or the classroom share (shared). Nil for a store the
    /// stack doesn't have.
    @MainActor
    static func lastImport(
        into store: SyncedStore,
        of stack: CoreDataStack,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Date? {
        let loaded: NSPersistentStore?
        switch store {
        case .notebook: loaded = stack.privatePersistentStore
        case .classroomShare: loaded = stack.sharedPersistentStore
        case .other: loaded = nil
        }
        guard let identifier = loaded?.identifier else { return nil }
        return lastImport(intoStoreWithIdentifier: identifier, now: now, defaults: defaults)
    }

    private static func stored(in defaults: UserDefaults) -> [String: TimeInterval] {
        defaults.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
    }
}

extension CloudKitSyncStatusService {

    /// Keeps the per-store dates a successful event moves: an import's start
    /// (`ImportWatermark`), and an export's start, before which the mirroring
    /// delegate has consumed the store's history, the bound for purging it
    /// (`PersistentHistoryProcessor.recordExportStart`; Apple's pattern in
    /// "Sharing Core Data objects between iCloud users"). Both only move
    /// forward, so a stale event can't regress them.
    func recordWatermark(type: NSPersistentCloudKitContainer.EventType, startDate: Date, storeIdentifier: String?) {
        let live = coreDataStack.map { stack in
            Set(stack.container.persistentStoreCoordinator.persistentStores.compactMap(\.identifier))
        }
        switch type {
        case .import:
            ImportWatermark.record(
                importStartedAt: startDate, storeIdentifier: storeIdentifier, liveStoreIdentifiers: live
            )
        case .export:
            PersistentHistoryProcessor.recordExportStart(
                startDate, storeIdentifier: storeIdentifier, liveStoreIdentifiers: live
            )
        default:
            break
        }
    }
}
