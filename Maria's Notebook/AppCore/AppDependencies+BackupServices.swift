import Foundation
import SwiftData

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

    var cloudBackupService: CloudBackupService {
        if let service = _cloudBackupService {
            return service
        }
        let service = CloudBackupService(backupService: backupService)
        _cloudBackupService = service
        return service
    }

    var incrementalBackupService: IncrementalBackupService {
        if let service = _incrementalBackupService {
            return service
        }
        let service = IncrementalBackupService(backupService: backupService)
        _incrementalBackupService = service
        return service
    }

    var backupSharingService: BackupSharingService {
        if let service = _backupSharingService {
            return service
        }
        let service = BackupSharingService(backupService: backupService)
        _backupSharingService = service
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

    var selectiveExportService: SelectiveExportService {
        if let service = _selectiveExportService {
            return service
        }
        let service = SelectiveExportService(backupService: backupService)
        _selectiveExportService = service
        return service
    }

    var autoBackupManager: AutoBackupManager {
        if let manager = _autoBackupManager {
            return manager
        }
        let manager = AutoBackupManager(backupService: backupService)
        _autoBackupManager = manager
        return manager
    }
}
