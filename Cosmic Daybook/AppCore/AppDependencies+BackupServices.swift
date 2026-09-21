import Foundation
import CoreData

// MARK: - Backup Services

extension AppDependencies {

    var autoBackupManager: AutoBackupManager { _autoBackupManager }

    /// Single app-facing backup entry point. UI and lifecycle code should talk
    /// to this coordinator rather than mixing legacy and v17 services directly.
    var backupCoordinator: BackupCoordinator { _backupCoordinator }
}
