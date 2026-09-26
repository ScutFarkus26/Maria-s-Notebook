import Foundation
@preconcurrency import CoreData
import OSLog

// MARK: - Persistent-history gate
//
// A repair pass used to fetch every classroom record and ask CloudKit which
// share zone each one lived in — after every save that inserted a shared
// entity, after every import, and every five seconds while the sharing screen
// was open. That is a full pass over ~30 entity tables plus a metadata join
// per record, on the main thread, many times a school day.
//
// Only an *insert* can create an orphan: a record that is already in a zone
// never leaves it, and updates, deletes, and CloudKit metadata writes do not
// move rows between zones. Persistent history records exactly which entities
// gained rows since any point in time. So every pass that ends with nothing
// left to attach stores the history token it started from as a "clean"
// watermark, and the next pass reads history since that watermark before it
// touches a single entity table. Nothing inserted → nothing to do. Something
// inserted → check only the inserted rows (history names them, so the pass
// never reads the rest of the table). History unavailable → scan everything,
// exactly as before, so a bad answer can never hide a real orphan.
//
// A pass whose history read finds no shared insert has nothing to attach
// either, so it records its starting token the same way (`advanceCleanToken`).
// Without that, every pass re-read everything since the last *scan* — a window
// that grew with each remote batch until the next shared insert. The read is
// scoped to the private store: detection only ever reports private-store rows
// (see `+Detection`), and the watermark only has a position in that store.
// Core Data already skips a store a token has no position in, so the scope
// changes no result; it states which history the gate depends on.

extension SharedStoreZoneRepair {

    /// What the history since the clean watermark says the next pass must do.
    nonisolated enum GateDecision: Equatable, Sendable {
        /// No shared entity has gained a row since the last clean pass.
        case clean
        /// Only these shared entities gained rows; scan just the rows that
        /// were inserted (`objectIDs`, every one belonging to one of
        /// `entityNames`). A row that existed at the watermark was already in
        /// a zone, so the inserted rows are the only possible orphans.
        case scan(entityNames: Set<String>, objectIDs: Set<NSManagedObjectID>)
        /// History could not answer — no watermark yet, a token from another
        /// store file, or a fetch error. Scan every shared entity.
        case scanEverything(reason: String)
    }

    nonisolated static let cleanTokenKey = UserDefaultsKeys.sharedStoreZoneRepairCleanHistoryToken

    /// The store's history position right now. Captured *before* a pass reads
    /// anything, so an insert that lands mid-scan is still ahead of the
    /// watermark the pass eventually records.
    nonisolated static func currentHistoryToken(
        for store: NSPersistentStore,
        in container: NSPersistentCloudKitContainer
    ) -> NSPersistentHistoryToken? {
        container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: [store])
    }

    /// The history read behind every gate decision: the transactions `store`
    /// recorded after `token`, with their changes. Scoped to `store` — the
    /// private store, where every row detection can report lives, and the
    /// only store the watermark has a position in.
    nonisolated static func gateHistoryRequest(
        after token: NSPersistentHistoryToken,
        in store: NSPersistentStore
    ) -> NSPersistentHistoryChangeRequest {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.resultType = .transactionsAndChanges
        request.affectedStores = [store]
        return request
    }

    /// Reads `store`'s persistent history after `token` and reports which
    /// shared entities were inserted. Runs on its own background context;
    /// never touches the entity tables themselves.
    nonisolated static func gateDecision(
        since token: NSPersistentHistoryToken?,
        store: NSPersistentStore,
        container: NSPersistentCloudKitContainer,
        sharedEntityNames: Set<String> = CoreDataStack.sharedEntityNames
    ) async -> GateDecision {
        guard let token else {
            return .scanEverything(reason: "no clean watermark yet")
        }
        let context = container.newBackgroundContext()
        return await context.perform {
            let request = gateHistoryRequest(after: token, in: store)
            do {
                guard let result = try context.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                    return .scanEverything(reason: "history result had an unexpected shape")
                }
                var inserted: Set<String> = []
                var insertedIDs: Set<NSManagedObjectID> = []
                for transaction in transactions {
                    for change in transaction.changes ?? [] where change.changeType == .insert {
                        let objectID = change.changedObjectID
                        if let name = objectID.entity.name, sharedEntityNames.contains(name) {
                            inserted.insert(name)
                            insertedIDs.insert(objectID)
                        }
                    }
                }
                return inserted.isEmpty ? .clean : .scan(entityNames: inserted, objectIDs: insertedIDs)
            } catch {
                // A token from a store file that no longer exists lands here.
                // Fail open to the full scan.
                return .scanEverything(reason: error.localizedDescription)
            }
        }
    }

    /// Moves the watermark up to `tokenBefore` after a `.clean` verdict;
    /// any other verdict leaves it where it is (a scanning pass records it
    /// itself, once the scan has found nothing left to attach).
    ///
    /// `tokenBefore` must be the store's token captured *before* the history
    /// read. The read then covered everything from the watermark up to it and
    /// found no shared insert, so every shared row that existed at
    /// `tokenBefore` already existed at the watermark — no row a scan could
    /// check is skipped. An insert that lands after the capture, whether
    /// during the read or between the read and this write, is after
    /// `tokenBefore` and still opens the gate next pass.
    nonisolated static func advanceCleanToken(
        after decision: GateDecision,
        to tokenBefore: NSPersistentHistoryToken?,
        defaults: UserDefaults = .standard
    ) {
        guard decision == .clean, let tokenBefore else { return }
        saveCleanToken(tokenBefore, defaults: defaults)
    }

    // MARK: Watermark persistence

    /// The token recorded by the last pass that left nothing to attach, or
    /// `nil` when no such pass has run on this store file.
    nonisolated static func loadCleanToken(defaults: UserDefaults = .standard) -> NSPersistentHistoryToken? {
        guard let data = defaults.data(forKey: cleanTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }

    nonisolated static func saveCleanToken(_ token: NSPersistentHistoryToken, defaults: UserDefaults = .standard) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            Self.logger.warning("SharedStoreZoneRepair: failed to archive the clean-pass history token")
            return
        }
        defaults.set(data, forKey: cleanTokenKey)
    }

    /// Forgets the watermark so the next pass scans everything. Called when
    /// the store file is replaced (Reset Local Cache). A backup restore needs
    /// no call: it imports rows into the existing store, and those inserts
    /// show up in history like any other.
    nonisolated static func clearCleanToken(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: cleanTokenKey)
    }
}
