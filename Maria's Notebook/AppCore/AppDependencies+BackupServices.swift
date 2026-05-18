import Foundation
import CoreData

// MARK: - Backup Services

extension AppDependencies {

    var backupService: BackupService {
        if let service = _backupService {
            return service
        }
        let service = BackupService()
        _backupService = service
        return service
    }

    var selectiveRestoreService: SelectiveRestoreService {
        if let service = _selectiveRestoreService {
            return service
        }
        let service = SelectiveRestoreService(backupService: backupService)
        _selectiveRestoreService = service
        return service
    }

    var backupTransactionManager: BackupTransactionManager {
        if let manager = _backupTransactionManager {
            return manager
        }
        let manager = BackupTransactionManager(backupService: backupService)
        _backupTransactionManager = manager
        return manager
    }

    var autoBackupManager: AutoBackupManager {
        if let manager = _autoBackupManager {
            return manager
        }
        // Lazy provider so the coordinator is created on demand without a
        // circular dependency at construction time.
        let manager = AutoBackupManager(
            backupService: backupService,
            coordinatorProvider: { [weak self] in self?.backupCoordinator }
        )
        _autoBackupManager = manager
        return manager
    }

    /// Top-level Backup2 entry point. New code (Settings export/import,
    /// AutoBackupManager) talks to this; it routes v17 AEA files through the
    /// Backup2 module and legacy `.mtbbackup` files through `backupService`.
    var backupCoordinator: BackupCoordinator {
        if let coordinator = _backupCoordinator {
            return coordinator
        }
        let coordinator = BackupCoordinator(
            backupService: backupService,
            transactionManager: backupTransactionManager,
            appRouter: appRouter
        )
        _backupCoordinator = coordinator
        return coordinator
    }
}
