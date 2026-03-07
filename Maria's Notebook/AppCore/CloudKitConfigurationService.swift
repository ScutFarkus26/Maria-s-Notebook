import Foundation
import OSLog
import CloudKit

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

    // Categorizes a CloudKit error for structured logging.
    // Uses CKError.Code enum rather than raw integers so the compiler catches
    // any code values that change or are removed across SDK versions.
    // swiftlint:disable:next cyclomatic_complexity
    private static func categorizeError(_ error: NSError) -> ErrorCategory {
        // Only treat CKErrorDomain errors as CloudKit errors
        guard error.domain == CKErrorDomain,
              let ckCode = CKError.Code(rawValue: error.code) else {
            // Non-CloudKit domain: fall back to domain heuristics
            if error.domain.contains("NSCocoaError") || error.domain.contains("NSPOSIXError") {
                return .network
            }
            return .unknown
        }

        switch ckCode {
        case .internalError:                    return .unknown
        case .partialFailure:                   return .unknown
        case .networkUnavailable:               return .network
        case .networkFailure:                   return .network
        case .badContainer:                     return .authentication
        case .serviceUnavailable:               return .network
        case .requestRateLimited:               return .quota
        case .notAuthenticated:                 return .authentication
        case .permissionFailure:                return .authentication
        case .unknownItem:                      return .conflict
        case .invalidArguments:                 return .schema
        case .serverRecordChanged:              return .conflict
        case .serverRejectedRequest:            return .schema
        case .assetFileNotFound:                return .unknown
        case .assetFileModified:                return .conflict
        case .incompatibleVersion:              return .schema
        case .constraintViolation:              return .schema
        case .operationCancelled:               return .unknown
        case .changeTokenExpired:               return .conflict
        case .batchRequestFailed:               return .unknown
        case .zoneBusy:                         return .network
        case .quotaExceeded:                    return .quota
        case .zoneNotFound:                     return .schema
        case .limitExceeded:                    return .quota
        case .userDeletedZone:                  return .conflict
        case .tooManyParticipants:              return .quota
        case .alreadyShared:                    return .conflict
        case .managedAccountRestricted:         return .authentication
        case .participantMayNeedVerification:   return .authentication
        case .accountTemporarilyUnavailable:    return .authentication
        @unknown default:                       return .unknown
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
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.cloudKitErrorLog)
        } catch {
            logger.warning("Failed to encode error log: \(error)")
        }
    }

    /// Retrieves the error log history
    static func getErrorLogs() -> [ErrorLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.cloudKitErrorLog) else {
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
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitErrorLog)
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
