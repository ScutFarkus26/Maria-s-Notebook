// BackupManager.swift (Deprecated)
// Maria's Notebook
//
// This file has been replaced by BackupService (data-only backup/restore).
// It remains in the project as a compile-time guard to catch any lingering references.

import Foundation
import SwiftData

@available(*, unavailable, message: "BackupManager has been replaced by BackupService. Use BackupService.exportBackup/importBackup instead.")
enum BackupManager {
    static let currentVersion: Int = 0

    @available(*, unavailable, message: "Use BackupService.exportBackup(modelContext:to:encrypt:progress:) instead.")
    static func makeBackupData(using context: ModelContext) throws -> Data { fatalError("BackupManager removed") }

    @available(*, unavailable, message: "Use BackupService.importBackup(modelContext:from:mode:progress:) instead.")
    static func restore(from data: Data, using context: ModelContext) throws { fatalError("BackupManager removed") }

    @available(*, unavailable, message: "Use BackupService.importBackup(modelContext:from:mode:progress:) with .replace instead.")
    static func deleteAll(using context: ModelContext) throws { fatalError("BackupManager removed") }
}

