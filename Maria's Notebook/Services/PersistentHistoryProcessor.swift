import Foundation
@preconcurrency import CoreData
import OSLog

/// Processes persistent history transactions from CloudKit remote changes.
/// Serialized via Swift actor to prevent concurrent history processing.
///
/// Responsibilities:
/// 1. Fetch remote history transactions since the last processed token
/// 2. Detect remote inserts and trigger DeduplicationCoordinator
/// 3. Persist the last processed token to UserDefaults
/// 4. Purge history older than our last processed token (safe for CloudKit)
///
/// CDNote: The view context has `automaticallyMergesChangesFromParent = true`,
/// which handles merging remote changes automatically. This processor only
/// inspects history to detect inserts for deduplication — it does NOT call
/// `mergeChanges(fromContextDidSave:)` (that would be redundant).
actor PersistentHistoryProcessor {

    // MARK: - Constants

    static let transactionAuthor = "MariasNotebook"
    nonisolated private static let logger = Logger.app(category: "HistoryProcessor")

    // MARK: - State

    private let container: NSPersistentCloudKitContainer
    private var lastToken: NSPersistentHistoryToken?

    // MARK: - Init

    init(container: NSPersistentCloudKitContainer) {
        self.container = container
        self.lastToken = Self.loadToken()
    }

    // MARK: - Public: Process Remote Changes

    /// Process new persistent history transactions since the last token.
    /// Called when `.NSPersistentStoreRemoteChange` fires.
    func processRemoteChanges() async {
        let context = container.newBackgroundContext()
        context.transactionAuthor = Self.transactionAuthor
        let currentToken = lastToken
        let author = Self.transactionAuthor

        let result: HistoryProcessingResult = await context.perform {
            Self.processHistory(after: currentToken, author: author, in: context)
        }

        switch result {
        case .noTransactions:
            break

        case let .processed(newToken, remoteCount, totalCount, hasInserts):
            lastToken = newToken
            Self.saveToken(newToken)

            Self.logger.debug(
                "Processed \(totalCount) history transaction(s), \(remoteCount) remote, inserts: \(hasInserts)"
            )

            if hasInserts {
                Task { @MainActor in
                    DeduplicationCoordinator.shared.requestDeduplication()
                }
            }

        case .failed:
            if lastToken != nil {
                Self.logger.info("Resetting stale history token for next attempt")
                lastToken = nil
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.persistentHistoryLastToken)
            }
        }
    }

    // MARK: - Public: Purge Old History

    /// Purge persistent history before our last processed token.
    /// Token-based purge is safe for CloudKit (date-based purge can break sync
    /// if the CloudKit mirroring delegate hasn't finished processing).
    func purgeOldHistory() async {
        guard let token = lastToken else {
            Self.logger.debug("Skipping history purge — no processed token yet")
            return
        }

        let context = container.newBackgroundContext()
        await context.perform {
            let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: token)
            do {
                try context.execute(purgeRequest)
                Self.logger.info("Purged persistent history before last processed token")
            } catch {
                Self.logger.error("Failed to purge history: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private: Core Data Processing (runs inside context.perform)

    /// Performs all Core Data work on the context's queue and returns Sendable results.
    /// Uses predicate-based author filtering at the store level (Apple recommended).
    private static func processHistory(
        after token: NSPersistentHistoryToken?,
        author: String,
        in context: NSManagedObjectContext
    ) -> HistoryProcessingResult {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.resultType = .transactionsAndChanges

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
                return advanceToken(after: token, in: context)
            }

            var hasInserts = false
            for transaction in transactions {
                if !hasInserts, let changes = transaction.changes {
                    for change in changes where change.changeType == .insert {
                        hasInserts = true
                        break
                    }
                }
            }

            guard let lastToken = transactions.last?.token else {
                return .noTransactions
            }

            return .processed(
                newToken: lastToken,
                remoteCount: transactions.count,
                totalCount: transactions.count,
                hasInserts: hasInserts
            )
        } catch {
            logger.error("Failed to process history: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Fetches the latest token even when there are no remote transactions,
    /// so purge can advance past our own transactions.
    private static func advanceToken(
        after token: NSPersistentHistoryToken?,
        in context: NSManagedObjectContext
    ) -> HistoryProcessingResult {
        let allRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        allRequest.resultType = .transactionsOnly

        guard let result = try? context.execute(allRequest) as? NSPersistentHistoryResult,
              let transactions = result.result as? [NSPersistentHistoryTransaction],
              let lastToken = transactions.last?.token else {
            return .noTransactions
        }

        return .processed(
            newToken: lastToken,
            remoteCount: 0,
            totalCount: transactions.count,
            hasInserts: false
        )
    }

    // MARK: - Private: Token Persistence

    private static func loadToken() -> NSPersistentHistoryToken? {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.persistentHistoryLastToken) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSPersistentHistoryToken.self,
            from: data
        )
    }

    private static func saveToken(_ token: NSPersistentHistoryToken) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        ) else {
            logger.warning("Failed to archive history token")
            return
        }
        UserDefaults.standard.set(data, forKey: UserDefaultsKeys.persistentHistoryLastToken)
    }
}

// MARK: - Result Type

/// Result of history processing — bridges Core Data work to actor state updates.
/// @unchecked because NSPersistentHistoryToken is not Sendable but is safely
/// transferred (created on one queue, consumed on another, no concurrent access).
private enum HistoryProcessingResult: @unchecked Sendable {
    case noTransactions
    case processed(
        newToken: NSPersistentHistoryToken,
        remoteCount: Int,
        totalCount: Int,
        hasInserts: Bool
    )
    case failed
}
