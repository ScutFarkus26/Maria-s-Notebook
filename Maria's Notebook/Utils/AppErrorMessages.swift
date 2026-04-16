// AppErrorMessages.swift
// Maps raw errors into user-friendly messages for toast and alert display.

import Foundation

enum AppErrorMessages {

    // MARK: - General Error Mapping

    /// Returns a user-friendly message for the given error.
    /// - Parameters:
    ///   - error: The underlying error
    ///   - context: Optional activity description (e.g. "loading lessons", "joining the classroom")
    static func userMessage(for error: Error, context: String? = nil) -> String {
        let nsError = error as NSError

        // Context phrase for embedding in sentences
        let activity = context ?? "completing this action"

        switch nsError.domain {

        // MARK: Network errors
        case NSURLErrorDomain:
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed:
                return "You appear to be offline. Check your connection and try \(activity) again."
            case NSURLErrorTimedOut:
                return "The request timed out while \(activity). Try again in a moment."
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return "Couldn't reach the server while \(activity). Try again later."
            default:
                return "A network issue prevented \(activity). Check your connection and try again."
            }

        // MARK: CloudKit errors
        case "CKErrorDomain":
            switch nsError.code {
            case 1: // CKError.internalError
                return "iCloud is temporarily unavailable. Your changes are saved locally and will sync when iCloud recovers."
            case 6: // CKError.notAuthenticated
                return "No iCloud account found. Sign in to iCloud in Settings to sync your data."
            case 9: // CKError.quotaExceeded
                return "Your iCloud storage is full. Free up space so your data can continue syncing."
            case 3, 7: // CKError.networkUnavailable, networkFailure
                return "Couldn't reach iCloud while \(activity). Your changes are saved locally."
            case 11: // CKError.zoneNotFound
                return "The shared classroom data isn't available yet. Ask the lead guide to re-share."
            case 15: // CKError.permissionFailure
                return "You don't have permission for this action. Check with the lead guide."
            default:
                return "An iCloud issue prevented \(activity). Your changes are saved locally and will sync later."
            }

        // MARK: Core Data errors
        case NSCocoaErrorDomain:
            if (256...1024).contains(nsError.code) {
                return "There was a problem reading your data. Try closing and reopening the app."
            }
            if nsError.code >= 1550 && nsError.code <= 1599 {
                return "Couldn't save your changes. Try again, or restart the app if the problem persists."
            }
            return "An unexpected issue occurred while \(activity). Try again."

        default:
            return "An unexpected issue occurred while \(activity). Try again."
        }
    }

    // MARK: - Domain-Specific Messages

    /// User-friendly message for save failures shown in the global save alert.
    static func saveFailureMessage(for error: Error, reason: String?) -> String {
        let base = userMessage(for: error, context: "saving your changes")
        if let why = reason, !why.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(base)\n\n(While: \(why))"
        }
        return base
    }

    /// User-friendly message for file import failures (lessons, resources, backups).
    static func importMessage(for error: Error, fileType: String = "file") -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return "The \(fileType) couldn't be found. It may have been moved or deleted."
            case NSFileReadNoPermissionError:
                return "The app doesn't have permission to read this \(fileType). Try selecting it again."
            case NSFileReadCorruptFileError:
                return "This \(fileType) appears to be damaged and can't be opened."
            default:
                break
            }
        }
        return "Couldn't import the \(fileType). Make sure it's a supported format and try again."
    }

    /// User-friendly message for AI/chat feature errors.
    static func aiMessage(for error: Error) -> String {
        let nsError = error as NSError

        // Network issues
        if nsError.domain == NSURLErrorDomain {
            return userMessage(for: error, context: "connecting to the AI service")
        }

        // API-specific errors (Anthropic, etc.)
        let desc = nsError.localizedDescription.lowercased()
        if desc.contains("api key") || desc.contains("unauthorized") || desc.contains("authentication") {
            return "Your API key may be invalid or expired. Check it in Settings \u{2192} AI Features."
        }
        if desc.contains("rate limit") || desc.contains("429") {
            return "Too many requests. Wait a moment and try again."
        }
        if desc.contains("model") && desc.contains("not found") {
            return "The selected AI model isn't available. Check your AI settings."
        }

        return "The AI feature encountered a problem. Check your connection and API settings, then try again."
    }

    /// User-friendly message for backup export/restore failures.
    static func backupMessage(for error: Error, operation: String) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteOutOfSpaceError:
                return "Not enough storage space to \(operation). Free up space and try again."
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return "The app doesn't have permission to access that location. Try a different folder."
            default:
                break
            }
        }
        return "Couldn't \(operation). Make sure you have enough storage space and try again."
    }

    /// User-friendly message for calendar/reminder sync failures.
    static func syncMessage(for error: Error, service: String) -> String {
        let nsError = error as NSError
        if nsError.domain == "EKErrorDomain" || nsError.domain == "EventKit" {
            return "\(service) sync couldn't complete. Check that the app has permission in Settings \u{2192} Privacy & Security."
        }
        return userMessage(for: error, context: "syncing \(service.lowercased())")
    }
}
