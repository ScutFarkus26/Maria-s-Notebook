import Foundation
import OSLog
import CloudKit

// MARK: - CloudKit Configuration Service

/// Service for managing CloudKit configuration and status.
enum CloudKitConfigurationService {

    private static let logger = Logger.app(category: "CloudKit")

    // MARK: - Container ID

    /// The one CloudKit container every target shares. Deliberately a literal,
    /// not derived from the bundle identifier: the assistant companion app has
    /// its own bundle ID but must read and write this same container, and its
    /// entitlements name it explicitly.
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

        var displayName: String {
            switch self {
            case .authentication: return "Authentication"
            case .network: return "Network"
            case .quota: return "Quota"
            case .conflict: return "Conflict"
            case .schema: return "Schema"
            case .unknown: return "Unknown"
            }
        }

        var recommendedAction: String {
            switch self {
            case .authentication:
                return "Sign in to iCloud and confirm this app has iCloud access."
            case .network:
                return "Check your internet connection and retry sync."
            case .quota:
                return "Free up iCloud storage space, then retry sync."
            case .conflict:
                return "Keep using the app; CloudKit should resolve this after a retry."
            case .schema:
                return "Update the app to the latest version and retry."
            case .unknown:
                return "Retry sync. If this persists, restart the app and check logs."
            }
        }
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
        let enabled = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.enableCloudKitSync
        ) as? Bool ?? true
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

        // Preserve retry guidance for transient CloudKit throttling failures.
        if nsError.domain == CKErrorDomain,
           let retryAfter = nsError.userInfo[CKErrorRetryAfterKey] as? NSNumber {
            detailedError += " (retry after \(retryAfter.doubleValue)s)"
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
            // Non-CloudKit domain errors should not be bucketed as network by default.
            return .unknown
        }

        // Map low-level CKError codes into user-facing categories used by Settings diagnostics.
        // Prefer stable high-level buckets so guidance remains actionable across transient failures.
        switch ckCode {
        case .internalError:                    return .unknown
        case .partialFailure:                   return categoryFromPartialFailure(error) ?? .unknown
        case .networkUnavailable:               return .network
        case .networkFailure:                   return .network
        case .badContainer:                     return .authentication
        case .serviceUnavailable:               return .network
        case .requestRateLimited:               return .network
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
        case .batchRequestFailed:               return categoryFromPartialFailure(error) ?? .conflict
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
        default:                                 return .unknown
        }
    }

    /// Resolves CKError.partialFailure/batchRequestFailed to a more useful category
    /// by inspecting per-item errors when available.
    private static func categoryFromPartialFailure(_ error: NSError) -> ErrorCategory? {
        guard let partialErrors = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] else {
            return nil
        }

        let prioritizedCategories: [ErrorCategory] = [
            .authentication, .quota, .network, .conflict, .schema
        ]
        let categories = partialErrors.values.map { categorizeError($0 as NSError) }
        return prioritizedCategories.first(where: { categories.contains($0) })
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

    /// Clears any stored CloudKit error.
    static func clearError() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
    }

}
