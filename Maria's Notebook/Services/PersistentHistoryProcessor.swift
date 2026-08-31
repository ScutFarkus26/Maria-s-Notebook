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
/// 4. Occasionally purge months-old history that the CloudKit mirroring
///    delegate has provably finished exporting (see `purgeOldHistory`)
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

    /// A pass is in flight. `.NSPersistentStoreRemoteChange` arrives in bursts during
    /// a CloudKit sync — one per imported batch — and each notification used to queue
    /// its own pass: a fresh background context plus a history fetch against SQLite,
    /// even though the first pass had already consumed the transactions the rest would
    /// look for. These two flags collapse a burst into at most one follow-up pass.
    private var isProcessing = false
    private var needsAnotherPass = false

    // MARK: - Init

    init(container: NSPersistentCloudKitContainer) {
        self.container = container
        self.lastToken = Self.loadToken()
    }

    // MARK: - Public: Process Remote Changes

    /// Process new persistent history transactions since the last token.
    /// Called when `.NSPersistentStoreRemoteChange` fires.
    ///
    /// Callers that arrive while a pass is running are folded into a single follow-up
    /// pass rather than each running their own. Nothing is dropped: the follow-up reads
    /// from the same token, so it still sees every transaction written in the meantime.
    func processRemoteChanges() async {
        guard !isProcessing else {
            needsAnotherPass = true
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        repeat {
            needsAnotherPass = false
            await performProcessingPass()
        } while needsAnotherPass
    }

    private func performProcessingPass() async {
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

            // The companion app has no dedup coordinator: it writes only
            // attendance, through the store that already collapses duplicates
            // per student-day on read.
            #if !ASSISTANT_APP
            if hasInserts {
                Task { @MainActor in
                    DeduplicationCoordinator.shared.requestDeduplication()
                }
            }
            #endif

        case .failed:
            if lastToken != nil {
                Self.logger.info("Resetting stale history token for next attempt")
                lastToken = nil
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.persistentHistoryLastToken)
            }
        }
    }

    // MARK: - Public: Purge Old History

    /// How old a transaction must be before it is eligible for purging.
    /// Apple: "long enough for the history to become irrelevant, which can be
    /// several months for apps that people use on a regular basis."
    private static let purgeRetention: TimeInterval = 180 * 24 * 3600

    /// Minimum interval between purges. Apple: "Apps generally only need to
    /// purge the history several times a year."
    private static let purgeInterval: TimeInterval = 60 * 24 * 3600

    /// Purge persistent history following Apple's documented pattern for
    /// CloudKit-backed stores ("Sharing Core Data objects between iCloud
    /// users"): delete only transactions that predate BOTH the start of the
    /// last successful `.export` event AND a several-month retention window.
    ///
    /// `NSCloudKitMirroringDelegate` keeps its own history cursor that this
    /// process cannot read. Purging transactions it hasn't exported yet
    /// invalidates that cursor and forces a full reset against the CloudKit
    /// server — and any deletion whose only record was the purged tombstone
    /// resurrects on the next import. The export-date gate guarantees the
    /// delegate consumed everything we delete; the retention window keeps the
    /// history available for other consumers (BackupChangeTracker) and for
    /// devices that re-enable sync after running in the degraded local mode.
    func purgeOldHistory() async {
        let defaults = UserDefaults.standard

        // Never purge before CloudKit has demonstrably exported. On stores
        // that have never synced this keeps all history for a future first
        // export; disk cost is acceptable at this app's write volume.
        guard let exportStart = defaults.object(
            forKey: UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate
        ) as? TimeInterval else {
            Self.logger.debug("Skipping history purge — no successful CloudKit export recorded")
            return
        }

        if let lastPurge = defaults.object(
            forKey: UserDefaultsKeys.persistentHistoryLastPurgeDate
        ) as? TimeInterval,
           Date().timeIntervalSince1970 - lastPurge < Self.purgeInterval {
            return
        }

        let retentionCutoff = Date().addingTimeInterval(-Self.purgeRetention)
        let cutoff = min(Date(timeIntervalSince1970: exportStart), retentionCutoff)

        let context = container.newBackgroundContext()
        let purged: Bool = await context.perform {
            let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff)
            do {
                try context.execute(purgeRequest)
                return true
            } catch {
                Self.logger.error("Failed to purge history: \(error.localizedDescription)")
                return false
            }
        }

        if purged {
            defaults.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.persistentHistoryLastPurgeDate)
            Self.logger.info("Purged persistent history older than \(cutoff, privacy: .public)")
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
    /// so the next fetch doesn't rescan transactions we already skipped.
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
