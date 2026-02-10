// BackupErrors.swift
// Comprehensive typed error hierarchy for Swift 6 backup operations

import Foundation

/// Root error type for all backup-related operations
/// Enables typed throws for compile-time exhaustiveness checking
/// Note: Renamed to BackupOperationError to avoid conflict with GenericBackupCodec.BackupError
public enum BackupOperationError: Error, Sendable {
    // MARK: - Export Errors
    case exportFailed(ExportError)
    case importFailed(ImportError)
    case validationFailed(ValidationError)
    case cloudOperationFailed(CloudError)
    case transactionFailed(TransactionError)
    
    // MARK: - Nested Error Types
    
    /// Errors that occur during backup export
    public enum ExportError: Error, Sendable {
        case contextUnavailable
        case entityFetchFailed(entityType: String, underlying: Error)
        case encodingFailed(underlying: Error)
        case compressionFailed(underlying: Error)
        case encryptionFailed(reason: String)
        case writeToFileFailed(url: URL, underlying: Error)
        case insufficientDiskSpace(required: Int64, available: Int64)
        case accessDenied(url: URL)
    }
    
    /// Errors that occur during backup import/restore
    public enum ImportError: Error, Sendable {
        case fileNotFound(url: URL)
        case fileCorrupted(reason: String)
        case invalidFormat(expected: Int, found: Int)
        case checksumMismatch
        case decryptionFailed(reason: String)
        case decompressionFailed(underlying: Error)
        case decodingFailed(underlying: Error)
        case entityInsertFailed(entityType: String, underlying: Error)
        case unsupportedVersion(version: Int)
        case missingDependencies([String])
    }
    
    /// Errors that occur during backup validation
    public enum ValidationError: Error, Sendable {
        case passwordRequired
        case passwordIncorrect
        case passwordTooWeak(reason: String)
        case checksumMismatch(expected: String, actual: String)
        case schemaVersionMismatch
        case missingRequiredData(field: String)
        case integrityCheckFailed(reason: String)
    }
    
    /// Errors specific to iCloud operations
    public enum CloudError: Error, Sendable {
        case iCloudNotAvailable
        case containerNotFound
        case uploadFailed(underlying: Error)
        case downloadFailed(underlying: Error)
        case quotaExceeded
        case networkUnavailable
        case conflictDetected(localURL: URL, cloudURL: URL)
        case syncFailed(reason: String)
    }
    
    /// Errors during transaction management
    public enum TransactionError: Error, Sendable {
        case checkpointCreationFailed(underlying: Error)
        case rollbackFailed(underlying: Error)
        case noCheckpointExists
        case saveFailed(underlying: Error)
    }
}

// MARK: - LocalizedError Conformance

extension BackupOperationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .exportFailed(let error):
            return "Export failed: \(error.localizedDescription)"
        case .importFailed(let error):
            return "Import failed: \(error.localizedDescription)"
        case .validationFailed(let error):
            return "Validation failed: \(error.localizedDescription)"
        case .cloudOperationFailed(let error):
            return "Cloud operation failed: \(error.localizedDescription)"
        case .transactionFailed(let error):
            return "Transaction failed: \(error.localizedDescription)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .exportFailed(.insufficientDiskSpace(let required, let available)):
            let formatter = ByteCountFormatter()
            return "Free up at least \(formatter.string(fromByteCount: required - available)) of disk space."
        case .validationFailed(.passwordRequired):
            return "This backup is encrypted. Please provide the password."
        case .validationFailed(.passwordIncorrect):
            return "The password you entered is incorrect. Please try again."
        case .cloudOperationFailed(.iCloudNotAvailable):
            return "Sign in to iCloud in System Settings to use cloud backup."
        default:
            return nil
        }
    }
}

extension BackupOperationError.ExportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .contextUnavailable:
            return "Database context is not available"
        case .entityFetchFailed(let type, let error):
            return "Failed to fetch \(type): \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to encode backup data: \(error.localizedDescription)"
        case .compressionFailed(let error):
            return "Failed to compress backup: \(error.localizedDescription)"
        case .encryptionFailed(let reason):
            return "Failed to encrypt backup: \(reason)"
        case .writeToFileFailed(let url, let error):
            return "Failed to write backup to \(url.path): \(error.localizedDescription)"
        case .insufficientDiskSpace(let required, let available):
            let formatter = ByteCountFormatter()
            return "Insufficient disk space. Need \(formatter.string(fromByteCount: required)), have \(formatter.string(fromByteCount: available))"
        case .accessDenied(let url):
            return "Access denied to \(url.path)"
        }
    }
}

extension BackupOperationError.ImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Backup file not found: \(url.path)"
        case .fileCorrupted(let reason):
            return "Backup file is corrupted: \(reason)"
        case .invalidFormat(let expected, let found):
            return "Invalid backup format. Expected version \(expected), found \(found)"
        case .checksumMismatch:
            return "Backup file failed integrity check"
        case .decryptionFailed(let reason):
            return "Failed to decrypt backup: \(reason)"
        case .decompressionFailed(let error):
            return "Failed to decompress backup: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode backup data: \(error.localizedDescription)"
        case .entityInsertFailed(let type, let error):
            return "Failed to import \(type): \(error.localizedDescription)"
        case .unsupportedVersion(let version):
            return "Unsupported backup version: \(version)"
        case .missingDependencies(let deps):
            return "Missing required data: \(deps.joined(separator: ", "))"
        }
    }
}

extension BackupOperationError.ValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return "This backup requires a password"
        case .passwordIncorrect:
            return "Incorrect password"
        case .passwordTooWeak(let reason):
            return "Password is too weak: \(reason)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch. Expected \(expected), got \(actual)"
        case .schemaVersionMismatch:
            return "Database schema version mismatch"
        case .missingRequiredData(let field):
            return "Missing required field: \(field)"
        case .integrityCheckFailed(let reason):
            return "Integrity check failed: \(reason)"
        }
    }
}

extension BackupOperationError.CloudError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud is not available"
        case .containerNotFound:
            return "Could not access iCloud container"
        case .uploadFailed(let error):
            return "Upload to iCloud failed: \(error.localizedDescription)"
        case .downloadFailed(let error):
            return "Download from iCloud failed: \(error.localizedDescription)"
        case .quotaExceeded:
            return "iCloud storage quota exceeded"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .conflictDetected(let local, let cloud):
            return "Sync conflict between \(local.lastPathComponent) and \(cloud.lastPathComponent)"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        }
    }
}

extension BackupOperationError.TransactionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .checkpointCreationFailed(let error):
            return "Failed to create checkpoint: \(error.localizedDescription)"
        case .rollbackFailed(let error):
            return "Rollback failed: \(error.localizedDescription)"
        case .noCheckpointExists:
            return "No checkpoint available for rollback"
        case .saveFailed(let error):
            return "Failed to save changes: \(error.localizedDescription)"
        }
    }
}

// MARK: - Convenience Helpers

extension BackupOperationError {
    /// Check if this error is recoverable by user action
    public var isRecoverable: Bool {
        switch self {
        case .exportFailed(.insufficientDiskSpace):
            return true
        case .validationFailed(.passwordRequired), .validationFailed(.passwordIncorrect):
            return true
        case .cloudOperationFailed(.iCloudNotAvailable), .cloudOperationFailed(.networkUnavailable):
            return true
        default:
            return false
        }
    }
    
    /// Check if this error should trigger a retry
    public var shouldRetry: Bool {
        switch self {
        case .cloudOperationFailed(.networkUnavailable):
            return true
        case .cloudOperationFailed(.uploadFailed), .cloudOperationFailed(.downloadFailed):
            return true
        case .exportFailed(.writeToFileFailed):
            return true
        default:
            return false
        }
    }
}
