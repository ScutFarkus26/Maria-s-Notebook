import Foundation
@preconcurrency import CoreData
import OSLog

// MARK: - One history position per store
//
// A persistent-history token holds a position only in the store its
// transaction came from, and a fetch that is given a token reads exactly the
// stores the token names: `affectedStores` changes nothing then, and only
// narrows a fetch that has no token. The processor used to keep one token, the
// newest transaction's, for both stores. After any pass whose newest
// transaction was in one store, every later fetch read that store alone and
// returned nothing from the other, with no error, so the fail-open reset never
// fired. That store's remote changes then got no scoped dedup, no zone-repair
// trigger, and no entity notifications.
//
// So each store keeps its own position, keyed by `NSPersistentStore.identifier`,
// and each pass reads each store on its own: after that store's token, or,
// with none, from its beginning with `affectedStores` naming it. This is the
// pattern of Apple's two-store sharing sample, which "maintains the token of
// the last transaction it consumes for each store". A position is only ever
// the token of a transaction read from its own store, never a coordinator
// token or another store's. `PersistentHistoryTokenScopeTests` pins the Core
// Data behaviour; `PersistentHistoryStoreCursorTests` pins this cursor.

extension PersistentHistoryProcessor {

    /// What one pass owes, across every store it read.
    nonisolated enum PassOutcome: Equatable, Sendable {
        /// No store had a transaction after its position.
        case noTransactions
        /// At least one store's position moved. The counts and entity names
        /// cover every store the pass read.
        case processed(
            remoteCount: Int,
            totalCount: Int,
            insertedEntityNames: Set<String>,
            changedEntityNames: Set<String>
        )
        /// A store's history could not be read.
        case failed
    }

    /// What one pass read across every loaded store.
    ///
    /// `@unchecked Sendable` because `NSPersistentHistoryToken` is not
    /// `Sendable`; the tokens are created on the context's queue and only
    /// read once the pass has handed them to the actor.
    nonisolated struct HistoryPass: @unchecked Sendable {
        /// Store identifier → the token of the last transaction read from
        /// that store. A store without an entry is read from its beginning
        /// next time: one never read, or one whose read just failed. Only
        /// the loaded stores have entries.
        let positions: [String: NSPersistentHistoryToken]
        let outcome: PassOutcome
    }

    /// Reads every loaded store's history after that store's own position.
    /// Performs all Core Data work on `context`'s queue.
    nonisolated static func readHistory(
        after positions: [String: NSPersistentHistoryToken],
        author: String,
        in context: NSManagedObjectContext
    ) -> HistoryPass {
        var next: [String: NSPersistentHistoryToken] = [:]
        var remoteCount = 0
        var totalCount = 0
        var inserted: Set<String> = []
        var changed: Set<String> = []
        var advanced = false
        var failed = false

        for store in context.persistentStoreCoordinator?.persistentStores ?? [] {
            guard let storeID = store.identifier else { continue }
            let position = positions[storeID]
            switch readHistory(of: store, after: position, author: author, in: context) {
            case .noTransactions:
                next[storeID] = position
            case let .processed(newToken, storeRemoteCount, storeTotalCount, storeInserted, storeChanged):
                next[storeID] = newToken
                advanced = true
                remoteCount += storeRemoteCount
                totalCount += storeTotalCount
                inserted.formUnion(storeInserted)
                changed.formUnion(storeChanged)
            case .failed:
                // No entry: the next pass reads this store from its beginning.
                failed = true
                if position != nil {
                    logger.info("Resetting stale history token for next attempt")
                }
            }
        }

        let outcome: PassOutcome
        if failed {
            outcome = .failed
        } else if advanced {
            outcome = .processed(
                remoteCount: remoteCount,
                totalCount: totalCount,
                insertedEntityNames: inserted,
                changedEntityNames: changed
            )
        } else {
            outcome = .noTransactions
        }
        return HistoryPass(positions: next, outcome: outcome)
    }

    /// One store's transactions after `token`, leaving out `author`'s own
    /// with predicate-based filtering at the store level (Apple recommended).
    nonisolated private static func readHistory(
        of store: NSPersistentStore,
        after token: NSPersistentHistoryToken?,
        author: String,
        in context: NSManagedObjectContext
    ) -> StoreHistoryResult {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.resultType = .transactionsAndChanges
        request.affectedStores = [store]

        // Filter out our own transactions at the store level (more efficient than in-memory)
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            fetchRequest.predicate = NSPredicate(format: "author != %@", author)
            request.fetchRequest = fetchRequest
        }

        do {
            guard let result = try context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction],
                  !transactions.isEmpty else {
                // Still need to advance the token even if no remote transactions
                return advanceToken(of: store, after: token, author: author, in: context)
            }

            let (insertedEntityNames, changedEntityNames) = entityNames(in: transactions)

            guard let lastToken = transactions.last?.token else {
                return .noTransactions
            }

            return .processed(
                newToken: lastToken,
                remoteCount: transactions.count,
                totalCount: transactions.count,
                insertedEntityNames: insertedEntityNames,
                changedEntityNames: changedEntityNames
            )
        } catch {
            let storeName: String = store.configurationName
            logger.error(
                "Failed to process \(storeName, privacy: .public) history: \(error.localizedDescription)"
            )
            return .failed
        }
    }

    /// The entities the transactions inserted into, and every entity they touched.
    nonisolated private static func entityNames(
        in transactions: [NSPersistentHistoryTransaction]
    ) -> (inserted: Set<String>, changed: Set<String>) {
        var inserted: Set<String> = []
        var changed: Set<String> = []
        let changes: [NSPersistentHistoryChange] = transactions.flatMap { $0.changes ?? [] }
        for change in changes {
            guard let name: String = change.changedObjectID.entity.name else { continue }
            changed.insert(name)
            let isInsert: Bool = change.changeType == .insert
            if isInsert { inserted.insert(name) }
        }
        return (inserted, changed)
    }

    /// Moves the store's position past what the filtered fetch leaves out, so
    /// the next fetch doesn't rescan it: `author`'s own transactions, and nil
    /// authors, which the store-level `author != %@` leaves out too.
    ///
    /// Only through their leading run. This is a second read, so a transaction
    /// the filter would return committed after the filtered read ran: most
    /// likely a CloudKit import, whose own remote-change notification schedules
    /// the pass that reads it. Moving past it would lose its scoped dedup,
    /// zone-repair trigger and entity notifications for good.
    nonisolated static func advanceToken(
        of store: NSPersistentStore,
        after token: NSPersistentHistoryToken?,
        author: String,
        in context: NSManagedObjectContext
    ) -> StoreHistoryResult {
        let allRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        allRequest.resultType = .transactionsOnly
        allRequest.affectedStores = [store]

        guard let result = try? context.execute(allRequest) as? NSPersistentHistoryResult,
              let transactions = result.result as? [NSPersistentHistoryTransaction] else {
            return .noTransactions
        }
        let filteredOut = transactions.prefix { $0.author == nil || $0.author == author }
        guard let lastToken = filteredOut.last?.token else {
            return .noTransactions
        }

        return .processed(
            newToken: lastToken,
            remoteCount: 0,
            totalCount: filteredOut.count,
            insertedEntityNames: [],
            changedEntityNames: []
        )
    }

    // MARK: - Positions in UserDefaults

    /// The saved positions: each store's archived token under its identifier.
    /// An entry that no longer unarchives is left out, so that store is read
    /// from its beginning.
    nonisolated static func loadPositions(from defaults: UserDefaults) -> [String: NSPersistentHistoryToken] {
        let archived = defaults.dictionary(forKey: UserDefaultsKeys.persistentHistoryStoreTokens) ?? [:]
        var positions: [String: NSPersistentHistoryToken] = [:]
        for (storeID, value) in archived {
            guard let data = value as? Data,
                  let token = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSPersistentHistoryToken.self,
                    from: data
                  ) else { continue }
            positions[storeID] = token
        }
        return positions
    }

    nonisolated static func savePositions(
        _ positions: [String: NSPersistentHistoryToken],
        to defaults: UserDefaults
    ) {
        var archived: [String: Data] = [:]
        for (storeID, token) in positions {
            guard let data = try? NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            ) else {
                logger.warning("Failed to archive history token")
                continue
            }
            archived[storeID] = data
        }
        if archived.isEmpty {
            defaults.removeObject(forKey: UserDefaultsKeys.persistentHistoryStoreTokens)
        } else {
            defaults.set(archived, forKey: UserDefaultsKeys.persistentHistoryStoreTokens)
        }
    }
}

// MARK: - Result Type

/// One store's history read — bridges Core Data work to the pass's result.
/// Internal for `PersistentHistoryAdvanceTests`.
/// @unchecked because NSPersistentHistoryToken is not Sendable but is safely
/// transferred (created on one queue, consumed on another, no concurrent access).
nonisolated enum StoreHistoryResult: @unchecked Sendable {
    case noTransactions
    case processed(
        newToken: NSPersistentHistoryToken,
        remoteCount: Int,
        totalCount: Int,
        insertedEntityNames: Set<String>,
        changedEntityNames: Set<String>
    )
    case failed
}
