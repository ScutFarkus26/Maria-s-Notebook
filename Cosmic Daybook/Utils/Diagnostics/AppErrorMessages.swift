// AppErrorMessages.swift
// Maps raw errors into plain-English messages for toast and alert display.
//
// The rule (Danny's): every message says what happened and what, if anything,
// to do, in everyday words. No raw system text, codes, file paths or type
// names ever reach the screen; they go to the log where the error is caught.
// Anything not mapped here gets a plain general sentence, never the raw text.

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
        let activity = context ?? "doing that"

        if let localized = appDefinedDescription(of: error) {
            return localized
        }

        switch nsError.domain {
        case NSURLErrorDomain:
            return networkMessage(code: nsError.code, activity: activity)
        case "CKErrorDomain":
            return cloudKitMessage(code: nsError.code, activity: activity)
        case NSCocoaErrorDomain:
            return cocoaMessage(code: nsError.code, activity: activity)
        default:
            return unexpectedMessage(activity: activity)
        }
    }

    /// The text of an app-defined `LocalizedError`, or nil for a bridged
    /// system error (CKError, NSURLError, CocoaError also conform to
    /// `LocalizedError`, but their text is raw system wording — the domain
    /// switches translate those instead).
    private static func appDefinedDescription(of error: Error) -> String? {
        let systemDomains: Set<String> = [NSURLErrorDomain, "CKErrorDomain", NSCocoaErrorDomain]
        guard !systemDomains.contains((error as NSError).domain),
              let localized = (error as? LocalizedError)?.errorDescription,
              !localized.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return localized
    }

    /// The fallback for a domain — or a code — we have nothing specific to say about.
    private static func unexpectedMessage(activity: String) -> String {
        "Something went wrong while \(activity). Try again."
    }

    /// "Settings" on iPhone and iPad, "System Settings" on the Mac. (The
    /// Assistant compiles this file, so it can't use `SystemSettingsApp`.)
    private static var settingsApp: String {
        #if os(macOS)
        "System Settings"
        #else
        "Settings"
        #endif
    }

    // MARK: Network errors

    private static func networkMessage(code: Int, activity: String) -> String {
        switch code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed:
            return "You appear to be offline. Check your connection and try \(activity) again."
        case NSURLErrorTimedOut:
            return "The connection was too slow while \(activity). Try again in a moment."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "Couldn't connect while \(activity). Try again later."
        default:
            return "A connection problem stopped \(activity). Check your connection and try again."
        }
    }

    // MARK: CloudKit errors

    /// Codes are `CKError.Code` raw values; CloudKit is not imported here.
    /// Until 2026-09-29 most of them were off (9, "not signed in", read as a
    /// full iCloud account; 6, "service unavailable", as not signed in).
    private static func cloudKitMessage(code: Int, activity: String) -> String {
        switch code {
        case 1, 6, 7: // internalError, serviceUnavailable, requestRateLimited
            return "iCloud is temporarily unavailable. Your changes are saved on this device and " +
                "will sync when iCloud recovers."
        case 9: // notAuthenticated
            return "This device isn't signed in to iCloud. Sign in from \(settingsApp) to sync your notebook."
        case 25: // quotaExceeded
            return "Your iCloud storage is full. Free up space so your notebook can keep syncing."
        case 3, 4: // networkUnavailable, networkFailure
            return "Couldn't reach iCloud while \(activity). Your changes are saved on this device."
        case 26, 28: // zoneNotFound, userDeletedZone
            return "The shared classroom isn't available yet. Ask the lead guide to share it again."
        case 10: // permissionFailure
            return "You don't have permission for this. Check with the lead guide."
        case 37: // participantAlreadyInvited (iOS/macOS 26)
            return "An invitation is already waiting to be accepted. Open the classroom link " +
                "to accept it, then try again."
        default:
            return "iCloud couldn't finish \(activity). Your changes are saved on this device and will sync later."
        }
    }

    /// The error that says what went wrong, out of the wrappers it arrives
    /// in: a CloudKit partial failure (code 2) holds one error per record,
    /// and a Core Data error holds CloudKit's under `NSUnderlyingErrorKey`.
    /// Matched as they came, a join that failed for want of a network read
    /// "The classroom couldn't be joined" with advice to ask for a new
    /// invitation.
    nonisolated static func innermostError(_ error: Error) -> NSError {
        var current = error as NSError
        for _ in 0..<4 {
            if current.domain == "CKErrorDomain", current.code == 2,
               // CKPartialErrorsByItemIDKey; CloudKit isn't imported here.
               let byItem = current.userInfo["CKPartialErrors"] as? [AnyHashable: Error],
               let item = byItem.values.map({ $0 as NSError }).min(by: { partialRank($0) < partialRank($1) }) {
                current = item
            } else if current.domain == NSCocoaErrorDomain,
                      let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                current = underlying
            } else {
                break
            }
        }
        return current
    }

    /// A record's own error before "batch request failed" (code 22), which
    /// only says another record in the batch failed; then by code, so the
    /// pick doesn't depend on the dictionary's order.
    nonisolated private static func partialRank(_ error: NSError) -> Int {
        error.domain == "CKErrorDomain" && error.code == 22 ? 1_000 + error.code : error.code
    }

    /// Why joining a classroom from an invitation failed. Unlike
    /// `userMessage` it never says "saved locally": a failed join saves
    /// nothing and nothing retries it. Each message is one sentence, and the
    /// screen showing it adds the fix (a fresh invitation).
    static func joinMessage(for error: Error) -> String {
        let nsError = innermostError(error)
        switch (nsError.domain, nsError.code) {
        case (NSURLErrorDomain, _), ("CKErrorDomain", 3), ("CKErrorDomain", 4):
            return "This device couldn't reach iCloud to join the classroom."
        case ("CKErrorDomain", 9):
            return "This device isn't signed in to iCloud."
        case ("CKErrorDomain", 1), ("CKErrorDomain", 6), ("CKErrorDomain", 7):
            return "iCloud was busy and the join didn't finish."
        case ("CKErrorDomain", 11), ("CKErrorDomain", 26), ("CKErrorDomain", 28):
            return "That invitation's classroom isn't available any longer."
        case ("CKErrorDomain", 10):
            return "That invitation isn't for this Apple Account."
        default:
            return "The classroom couldn't be joined."
        }
    }

    /// Why a sharing action — setting up the share, adding or removing a
    /// member, stopping sharing, leaving — failed. Like `joinMessage` it never
    /// says "saved locally": a failed sharing action saved nothing and nothing
    /// retries it. `action` is the verb phrase: "add Sam", "stop sharing".
    /// Looks inside the same wrappers as `joinMessage`.
    static func sharingMessage(for error: Error, action: String) -> String {
        if let localized = appDefinedDescription(of: error) {
            return localized
        }
        let nsError = innermostError(error)
        switch (nsError.domain, nsError.code) {
        case (NSURLErrorDomain, _), ("CKErrorDomain", 3), ("CKErrorDomain", 4):
            return "Couldn't \(action). This device couldn't reach iCloud. Check you're online and try again."
        case ("CKErrorDomain", 9):
            return "Couldn't \(action). This device isn't signed in to iCloud. " +
                "Sign in from \(settingsApp), then try again."
        case ("CKErrorDomain", 25):
            return "Couldn't \(action). Your iCloud storage is full. Free up space, then try again."
        case ("CKErrorDomain", 10):
            return "Couldn't \(action). This Apple Account isn't allowed to change who the classroom is shared with."
        case ("CKErrorDomain", 37):
            return "Couldn't \(action). An invitation is already waiting to be accepted."
        default:
            return "Couldn't \(action). iCloud didn't answer. Check you're online and try again."
        }
    }

    // MARK: Cocoa (file and Core Data) errors

    private static func cocoaMessage(code: Int, activity: String) -> String {
        switch code {
        case NSFileWriteOutOfSpaceError:
            return "This device is out of space. Free some up and try again."
        case NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError:
            return "Cosmic Daybook isn't allowed to save there. Try a different place."
        case 256...511: // file read errors (NSFileReadUnknownError…)
            return "There was a problem reading your notebook. Try closing and reopening the app."
        case 512...767: // file write errors (NSFileWriteUnknownError…)
            return "Couldn't save your changes. Try again, or restart the app if it keeps happening."
        case NSValidationErrorMinimum...NSValidationErrorMaximum:
            return "Couldn't save your changes. Try again, or restart the app if it keeps happening."
        default:
            return unexpectedMessage(activity: activity)
        }
    }

    // MARK: - Domain-Specific Messages

    /// The message for the global "Couldn't Save" alert. The caller's `reason`
    /// is a developer label ("Toggle pin status"), so it goes to the log
    /// (`SaveCoordinator` logs it), never into the message.
    static func saveFailureMessage(for error: Error) -> String {
        userMessage(for: error, context: "saving your changes")
    }

    /// User-friendly message for file import failures (lessons, resources, backups).
    static func importMessage(for error: Error, fileType: String = "file") -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return "Couldn't find the \(fileType). It may have been moved or deleted."
            case NSFileReadNoPermissionError:
                return "Cosmic Daybook can't open this \(fileType). Choose it again."
            case NSFileReadCorruptFileError:
                return "This \(fileType) looks damaged and can't be opened."
            case NSFileWriteOutOfSpaceError:
                return "There isn't enough space to add this \(fileType). Free up some space and try again."
            default:
                break
            }
        }
        return "Couldn't add the \(fileType). Make sure it's the right kind of file and try again."
    }

    // No AI in the assistant's companion app, and LocalModelError lives with
    // the model clients it doesn't build.
    #if !ASSISTANT_APP

    /// The message for an Apple Intelligence feature's failure. Apple
    /// Intelligence's own errors speak for themselves; an app-defined error
    /// (a student who isn't there any more) speaks for itself too; anything
    /// else gets the caller's `fallback`, never raw text.
    static func aiMessage(
        for error: Error,
        fallback: String = AppleIntelligenceMessages.fallback
    ) -> String {
        if let localError = error as? LocalModelError {
            return localError.errorDescription ?? fallback
        }
        if let modelMessage = AppleIntelligenceMessages.message(forAny: error, fallback: fallback) {
            return modelMessage
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return userMessage(for: error, context: "reaching Apple Intelligence")
        }
        return appDefinedDescription(of: error) ?? fallback
    }

    #endif

    /// User-friendly message for backup export/restore failures. The backup
    /// errors are app-defined and already plain, so they speak for themselves;
    /// file errors are translated; anything else is the general sentence.
    static func backupMessage(for error: Error, operation: String) -> String {
        if let localized = appDefinedDescription(of: error) {
            return localized
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteOutOfSpaceError:
                return "There isn't enough space to \(operation). Free up space and try again."
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError, NSFileWriteVolumeReadOnlyError:
                return "Cosmic Daybook isn't allowed to use that folder. Choose a different one."
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return "Couldn't find that backup file. It may have been moved or deleted."
            default:
                break
            }
        }
        return "Couldn't \(operation). Try again."
    }

    /// User-friendly message for calendar/reminder sync failures.
    static func syncMessage(for error: Error, service: String) -> String {
        let nsError = error as NSError
        if nsError.domain == "EKErrorDomain" || nsError.domain == "EventKit" {
            return "Couldn't update \(service). Check that Cosmic Daybook can use \(service) " +
                "in \(settingsApp) \u{203A} Privacy & Security."
        }
        return userMessage(for: error, context: "updating \(service)")
    }
}
