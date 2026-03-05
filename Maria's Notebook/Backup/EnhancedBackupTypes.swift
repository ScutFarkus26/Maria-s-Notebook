import Foundation

// MARK: - Enhanced Backup Result Types

public struct EnhancedBackupOperationSummary {
    public let summary: BackupOperationSummary
    public let exportMode: EnhancedBackupService.ExportMode
    public let verificationResult: ChecksumVerificationService.VerificationResult?
    public let verificationReport: BackupVerificationReport
    public let duration: TimeInterval
}

public struct EnhancedRestoreResult {
    public let success: Bool
    public let importMode: EnhancedBackupService.ImportMode
    public let importedEntities: [String: Int]
    public let failedEntities: [String: Int]
    public let validationResult: BackupValidationService.ValidationResult
    public let errors: [String]
    public let warnings: [String]
    public let duration: TimeInterval
    public let restorePointURL: URL?

    public var totalImported: Int {
        importedEntities.values.reduce(0, +)
    }

    public var totalFailed: Int {
        failedEntities.values.reduce(0, +)
    }
}

public struct EnhancedRestorePreview {
    public let preview: RestorePreview
    public let validation: BackupValidationService.ValidationResult
    public let conflicts: [CloudSyncConflictResolver.Conflict]
}

public struct BackupVerificationReport {
    public let url: URL
    public let createdAt: Date
    public let isValid: Bool
    public let duration: TimeInterval
    public let issues: [String]
    public let recommendations: [String]
}
