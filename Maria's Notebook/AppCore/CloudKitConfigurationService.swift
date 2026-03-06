import Foundation
import OSLog

// MARK: - CloudKit Configuration Service

/// Service for managing CloudKit configuration and status.
enum CloudKitConfigurationService {

    private static let logger = Logger.app(category: "CloudKit")

    // MARK: - Container ID

    /// Returns the CloudKit container identifier from entitlements.
    /// This must match the container ID in the entitlements file.
    static func getContainerID() -> String? {
        "iCloud.DanielSDeBerry.MariasNoteBook"
    }

    // MARK: - Status

    /// CloudKit sync status summary.
    struct Status {
        let enabled: Bool
        let active: Bool
        let containerID: String
    }

    // MARK: - Structured Error Log Entry

    /// Represents a structured CloudKit error for logging and diagnostics
    enum ErrorCategory: String, Codable {
        case authentication
        case network
        case quota
        case conflict
        case schema
        case unknown
    }

    struct ErrorLogEntry: Codable {
        let timestamp: Date
        let errorMessage: String
        let errorCode: Int?
        let errorDomain: String?
        let category: ErrorCategory
        let retryCount: Int
    }

    /// Maximum number of error log entries to keep
    private static let maxErrorLogEntries = 50

    /// Returns a summary of CloudKit sync status.
    static func getStatus() -> Status {
        let enabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
        let active = UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)
        let containerID = getContainerID() ?? "Unknown"
        return Status(enabled: enabled, active: active, containerID: containerID)
    }

    // MARK: - Error Handling

    /// Stores a CloudKit error for display in the UI and adds to error log.
    static func storeError(_ error: Error, retryCount: Int = 0) {
        let nsError = error as NSError
        let errorDescription = nsError.localizedDescription
        var detailedError = errorDescription

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            detailedError = underlyingError.localizedDescription
        } else if let errorMessage = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
            detailedError = errorMessage
        }

        // Store for UI display
        UserDefaults.standard.set(detailedError, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)

        // Categorize the error
        let category = categorizeError(nsError)

        // Create structured log entry
        let logEntry = ErrorLogEntry(
            timestamp: Date(),
            errorMessage: detailedError,
            errorCode: nsError.code,
            errorDomain: nsError.domain,
            category: category,
            retryCount: retryCount
        )

        // Add to error log
        appendErrorLog(logEntry)

        // Log to system logger
        let msg = "CloudKit error [\(category.rawValue)]: "
            + "\(detailedError) (code: \(nsError.code), domain: \(nsError.domain))"
        logger.error("\(msg)")
    }

    /// Categorizes a CloudKit error for structured logging
    private static func categorizeError(_ error: NSError) -> ErrorCategory {
        // CloudKit error codes (CKError)
        // https://developer.apple.com/documentation/cloudkit/ckerror
        switch error.code {
        case 1: // CKError.internalError
            return .unknown
        case 2: // CKError.partialFailure
            return .unknown
        case 3: // CKError.networkUnavailable
            return .network
        case 4: // CKError.networkFailure
            return .network
        case 5: // CKError.badContainer
            return .authentication
        case 6: // CKError.serviceUnavailable
            return .network
        case 7: // CKError.requestRateLimited
            return .quota
        case 9: // CKError.notAuthenticated
            return .authentication
        case 10: // CKError.permissionFailure
            return .authentication
        case 11: // CKError.unknownItem
            return .conflict
        case 12: // CKError.invalidArguments
            return .schema
        case 14: // CKError.serverRecordChanged
            return .conflict
        case 15: // CKError.serverRejectedRequest
            return .schema
        case 16: // CKError.assetFileNotFound
            return .unknown
        case 17: // CKError.assetFileModified
            return .conflict
        case 18: // CKError.incompatibleVersion
            return .schema
        case 19: // CKError.constraintViolation
            return .schema
        case 20: // CKError.operationCancelled
            return .unknown
        case 21: // CKError.changeTokenExpired
            return .conflict
        case 22: // CKError.batchRequestFailed
            return .unknown
        case 23: // CKError.zoneBusy
            return .network
        case 25: // CKError.quotaExceeded
            return .quota
        case 26: // CKError.zoneNotFound
            return .schema
        case 27: // CKError.limitExceeded
            return .quota
        case 28: // CKError.userDeletedZone
            return .conflict
        case 29: // CKError.tooManyParticipants
            return .quota
        case 30: // CKError.alreadyShared
            return .conflict
        case 32: // CKError.managedAccountRestricted
            return .authentication
        case 33: // CKError.participantMayNeedVerification
            return .authentication
        case 35: // CKError.accountTemporarilyUnavailable
            return .authentication
        default:
            // Check domain for additional categorization
            if error.domain.contains("NSCocoaError") || error.domain.contains("NSPOSIXError") {
                return .network
            }
            return .unknown
        }
    }

    /// Appends an error log entry to the persisted error history
    private static func appendErrorLog(_ entry: ErrorLogEntry) {
        var logs = getErrorLogs()
        logs.append(entry)

        // Trim to max entries
        if logs.count > maxErrorLogEntries {
            logs = Array(logs.suffix(maxErrorLogEntries))
        }

        // Persist
        do {
            let data = try JSONEncoder().encode(logs)
            UserDefaults.standard.set(data, forKey: "cloudKitErrorLog")
        } catch {
            logger.warning("Failed to encode error log: \(error)")
        }
    }

    /// Retrieves the error log history
    static func getErrorLogs() -> [ErrorLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: "cloudKitErrorLog") else {
            return []
        }
        do {
            let logs = try JSONDecoder().decode([ErrorLogEntry].self, from: data)
            return logs
        } catch {
            logger.warning("Failed to decode error log: \(error)")
            return []
        }
    }

    /// Clears the error log history
    static func clearErrorLog() {
        UserDefaults.standard.removeObject(forKey: "cloudKitErrorLog")
    }

    /// Returns a summary of recent errors by category
    static func getErrorSummary() -> [ErrorCategory: Int] {
        let logs = getErrorLogs()
        var summary: [ErrorCategory: Int] = [:]
        for log in logs {
            summary[log.category, default: 0] += 1
        }
        return summary
    }

    /// Clears any stored CloudKit error.
    static func clearError() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
    }

    /// Marks CloudKit as active and clears any previous error.
    static func markActive() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
        clearError()
        logger.info("CloudKit marked as active")
    }

    /// Marks CloudKit as inactive.
    static func markInactive() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
        logger.info("CloudKit marked as inactive")
    }
}
