// BackupChangeTracker.swift
// Decides whether an automatic backup is worth performing by consulting Core
// Data persistent history — the same change-tracking machinery
// NSPersistentCloudKitContainer already keeps enabled for mirroring.
//
// After each successful auto-backup the current history token is recorded.
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
    private static let tokenDefaultsKey = "AutoBackup.lastHistoryToken"

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

    /// Records the current history token as the new baseline. Call after a
    /// successful auto-backup.
    func recordBackupPoint(context: NSManagedObjectContext) {
        guard let coordinator = context.persistentStoreCoordinator else { return }
        // SQLite stores only — in-memory test stores don't track history.
        let stores = coordinator.persistentStores.filter { $0.type == NSSQLiteStoreType }
        guard !stores.isEmpty,
              let token = coordinator.currentPersistentHistoryToken(fromStores: stores) else {
            return
        }

        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
            UserDefaults.standard.set(data, forKey: Self.tokenDefaultsKey)
        } catch {
            Self.logger.warning(
                "Could not persist history token: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Token Persistence

    private func loadToken() -> NSPersistentHistoryToken? {
        guard let data = UserDefaults.standard.data(forKey: Self.tokenDefaultsKey) else { return nil }
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
        UserDefaults.standard.removeObject(forKey: Self.tokenDefaultsKey)
    }
}
