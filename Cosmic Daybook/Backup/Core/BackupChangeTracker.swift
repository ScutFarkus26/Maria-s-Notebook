// BackupChangeTracker.swift
// Decides whether an automatic backup is worth performing by consulting Core
// Data persistent history — the same change-tracking machinery
// NSPersistentCloudKitContainer already keeps enabled for mirroring.
//
// Before each auto-backup collects its rows the current history token is
// taken, and once the file is written that token is recorded. Taken after the
// write instead, a change saved while the backup was being written (an
// assistant's marks arriving) counted as backed up and waited for some other
// change before the next backup (2026-10-05 sync hunt).
// Before the next one, a single fetch-limit-1 history query answers "has any
// transaction (local edit OR change synced down from CloudKit) touched the
// stores since?". If not, the backup is skipped — a 4-hourly schedule on an
// idle classroom dataset becomes a series of no-ops instead of full exports.
//
// Fail-open by design: any uncertainty (no token yet, expired/pruned history,
// in-memory test store) reports "has changes" so a backup runs. A redundant
// backup is cheap; a missed one is the failure mode this subsystem exists to
// prevent.

import Foundation
import CoreData
import OSLog

final class BackupChangeTracker {
    private static let logger = Logger.backup
    /// Per CloudKit environment: a token from the other notebook names a
    /// different store.
    private static let tokenDefaultsKey = CloudKitEnvironment.scoped("AutoBackup.lastHistoryToken")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True when at least one persistent-history transaction exists after the
    /// recorded token — or when that can't be determined.
    func hasChangesSinceLastBackup(in context: NSManagedObjectContext) -> Bool {
        guard let token = loadToken() else { return true }

        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.resultType = .transactionsOnly
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            fetchRequest.fetchLimit = 1
            request.fetchRequest = fetchRequest
        }

        do {
            guard let result = try context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                return true
            }
            return !transactions.isEmpty
        } catch {
            // Most likely the token outlived the store's retained history.
            // Drop it and back up; the post-backup token will be fresh.
            Self.logger.warning(
                "History check failed; assuming changes exist: \(error.localizedDescription, privacy: .public)"
            )
            clearToken()
            return true
        }
    }

    /// The stores' current history token: everything saved up to now. Take it
    /// before the backup collects its rows and hand it to `recordBackupPoint`
    /// once the file is written. Nil when the stores keep no history (in-memory
    /// test stores), and then no baseline is recorded.
    func currentHistoryToken(context: NSManagedObjectContext) -> NSPersistentHistoryToken? {
        guard let coordinator = context.persistentStoreCoordinator else { return nil }
        // SQLite stores only — in-memory test stores don't track history.
        let stores = coordinator.persistentStores.filter { $0.type == NSSQLiteStoreType }
        guard !stores.isEmpty else { return nil }
        return coordinator.currentPersistentHistoryToken(fromStores: stores)
    }

    /// Records `token`, taken before the backup collected its rows, as the new
    /// baseline. Call after a successful auto-backup.
    func recordBackupPoint(_ token: NSPersistentHistoryToken?) {
        guard let token else { return }
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
            defaults.set(data, forKey: Self.tokenDefaultsKey)
        } catch {
            Self.logger.warning(
                "Could not persist history token: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Token Persistence

    private func loadToken() -> NSPersistentHistoryToken? {
        guard let data = defaults.data(forKey: Self.tokenDefaultsKey) else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self,
                from: data
            )
        } catch {
            let detail = error.localizedDescription
            Self.logger.warning("Stored history token unreadable; treating as no baseline: \(detail, privacy: .public)")
            clearToken()
            return nil
        }
    }

    private func clearToken() {
        defaults.removeObject(forKey: Self.tokenDefaultsKey)
    }
}
