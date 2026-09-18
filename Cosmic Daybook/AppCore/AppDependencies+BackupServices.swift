import Foundation
import CoreData

// MARK: - Backup Services

extension AppDependencies {

    private var backupService: BackupService {
        if let service = _backupService {
            return service
        }
        let service = BackupService()
        _backupService = service
        return service
    }

    private var backupTransactionManager: BackupTransactionManager {
        if let manager = _backupTransactionManager {
            return manager
        }
        let manager = BackupTransactionManager()
        _backupTransactionManager = manager
        return manager
    }

    var autoBackupManager: AutoBackupManager {
        if let manager = _autoBackupManager {
            return manager
        }
        let manager = AutoBackupManager(coordinator: backupCoordinator)
        _autoBackupManager = manager
        return manager
    }

    /// Single app-facing backup entry point. UI and lifecycle code should talk
    /// to this coordinator rather than mixing legacy and v17 services directly.
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
