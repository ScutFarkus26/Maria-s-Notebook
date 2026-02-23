//
//  SyncError.swift
//  Maria's Notebook
//
//  Created by Architecture Migration on 2026-02-13.
//

import Foundation

/// Errors related to CloudKit sync and network operations
enum SyncError: AppError {
    case notSignedIn
    case networkUnavailable
    case cloudKitUnavailable
    case accountChanged
    case quotaExceeded(used: Int64, limit: Int64)
    case conflictDetected(entity: String, localVersion: Date, remoteVersion: Date)
    case syncTimeout(duration: TimeInterval)
    case permissionDenied
    case incompatibleVersion(local: String, remote: String)
    case dataCorrupted(entity: String)
    case retryLimitExceeded(attempts: Int)
    
    var category: ErrorCategory {
        switch self {
        case .notSignedIn, .permissionDenied:
            return .permission
        case .networkUnavailable, .cloudKitUnavailable, .syncTimeout, .retryLimitExceeded:
            return .network
        case .accountChanged, .quotaExceeded, .conflictDetected, .incompatibleVersion:
            return .business
        case .dataCorrupted:
            return .database
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .notSignedIn, .networkUnavailable, .accountChanged, .quotaExceeded, .syncTimeout, .permissionDenied:
            return true
        case .cloudKitUnavailable, .conflictDetected, .incompatibleVersion, .dataCorrupted, .retryLimitExceeded:
            return false
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .notSignedIn, .networkUnavailable, .accountChanged:
            return .warning
        case .cloudKitUnavailable, .quotaExceeded, .syncTimeout, .retryLimitExceeded:
            return .error
        case .conflictDetected, .permissionDenied, .incompatibleVersion, .dataCorrupted:
            return .critical
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to iCloud"
            
        case .networkUnavailable:
            return "Network unavailable"
            
        case .cloudKitUnavailable:
            return "iCloud services unavailable"
            
        case .accountChanged:
            return "iCloud account changed"
            
        case .quotaExceeded:
            return "iCloud storage quota exceeded"
            
        case .conflictDetected(let entity, _, _):
            return "Sync conflict detected for \(entity)"
            
        case .syncTimeout(let duration):
            return "Sync timed out after \(Int(duration)) seconds"
            
        case .permissionDenied:
            return "Permission denied"
            
        case .incompatibleVersion:
            return "Incompatible data version"
            
        case .dataCorrupted(let entity):
            return "Data corruption detected in \(entity)"
            
        case .retryLimitExceeded(let attempts):
            return "Sync failed after \(attempts) attempts"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in to iCloud to sync data across devices."
            
        case .networkUnavailable:
            return "Your device is not connected to the internet."
            
        case .cloudKitUnavailable:
            return "iCloud services are currently unavailable. This may be due to Apple service issues."
            
        case .accountChanged:
            return "The iCloud account on this device has changed. Local data may differ from cloud data."
            
        case .quotaExceeded(let used, let limit):
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB]
            formatter.countStyle = .file
            return "You've used \(formatter.string(fromByteCount: used)) of \(formatter.string(fromByteCount: limit)) available iCloud storage."
            
        case .conflictDetected(let entity, let local, let remote):
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "Changes to \(entity) were made on this device (\(formatter.string(from: local))) and another device (\(formatter.string(from: remote)))."
            
        case .syncTimeout(let duration):
            return "The sync operation did not complete within \(Int(duration)) seconds."
            
        case .permissionDenied:
            return "This app does not have permission to access iCloud."
            
        case .incompatibleVersion(let local, let remote):
            return "Local data version (\(local)) is incompatible with cloud data version (\(remote))."
            
        case .dataCorrupted(let entity):
            return "The \(entity) data in iCloud appears to be corrupted or unreadable."
            
        case .retryLimitExceeded(let attempts):
            return "Sync failed after \(attempts) retry attempts due to persistent errors."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to iCloud in System Settings to enable sync."
            
        case .networkUnavailable:
            return "Connect to Wi-Fi or cellular data and try again."
            
        case .cloudKitUnavailable:
            return "Wait a few minutes and try again. Check Apple's system status page if the problem persists."
            
        case .accountChanged:
            return "Sign back in to your original iCloud account or create a backup before switching accounts."
            
        case .quotaExceeded:
            return "Free up iCloud storage or upgrade your iCloud+ plan to continue syncing."
            
        case .conflictDetected:
            return "Review the conflicting changes and choose which version to keep, or merge the changes manually."
            
        case .syncTimeout:
            return "Check your internet connection and try again. Large datasets may require a faster connection."
            
        case .permissionDenied:
            return "Enable iCloud access for Maria's Notebook in System Settings > iCloud."
            
        case .incompatibleVersion:
            return "Update the app on all devices to the latest version."
            
        case .dataCorrupted:
            return "Restore from a backup or contact support to recover your data."
            
        case .retryLimitExceeded:
            return "Wait a few minutes before trying again, or disable sync temporarily and re-enable it later."
        }
    }
}
