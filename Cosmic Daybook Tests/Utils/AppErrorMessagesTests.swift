import Foundation
import CloudKit
import Testing
@testable import CosmicDaybook

/// Pins the user-facing strings `AppErrorMessages` produces for one
/// representative input per branch, and the plain-English rule itself: no
/// message carries raw system text, codes or developer labels.
@MainActor
@Suite("App error messages")
struct AppErrorMessagesTests {

    private struct SampleError: LocalizedError {
        var errorDescription: String? { "The lesson file is missing a title row." }
    }

    /// Not a `LocalizedError`, so nothing can speak for it and the domain
    /// switch has to fall through to its default.
    private enum PlainError: Error { case boom }

    /// Words that mean raw system text leaked into a message.
    private static let rawMarkers = ["domain=", "code=", "Domain", "CKError", "NSCocoa", "(While:", "Error Domain"]

    private func expectPlain(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for marker in Self.rawMarkers {
            #expect(!message.contains(marker), "\"\(message)\" contains \(marker)", sourceLocation: sourceLocation)
        }
    }

    @Test("An app-defined LocalizedError speaks for itself")
    func localizedErrorWins() {
        #expect(AppErrorMessages.userMessage(for: SampleError(), context: "importing lessons")
            == "The lesson file is missing a title row.")
    }

    @Test("Being offline names the activity")
    func offlineNetworkError() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(AppErrorMessages.userMessage(for: error, context: "loading lessons")
            == "You appear to be offline. Check your connection and try loading lessons again.")
    }

    @Test("A full iCloud account is called out by name")
    func cloudKitQuotaExceeded() {
        let error = CKError(.quotaExceeded) as NSError
        #expect(AppErrorMessages.userMessage(for: error)
            == "Your iCloud storage is full. Free up space so your notebook can keep syncing.")
    }

    @Test("CloudKit codes read as what they are: signed out, offline, a gone zone")
    func cloudKitCodesMatchTheirNames() {
        #expect(AppErrorMessages.userMessage(for: CKError(.notAuthenticated) as NSError)
            .hasPrefix("This device isn't signed in to iCloud. Sign in from "))
        #expect(AppErrorMessages.userMessage(for: CKError(.networkFailure) as NSError, context: "joining")
            == "Couldn't reach iCloud while joining. Your changes are saved on this device.")
        #expect(AppErrorMessages.userMessage(for: CKError(.zoneNotFound) as NSError)
            == "The shared classroom isn't available yet. Ask the lead guide to share it again.")
        #expect(AppErrorMessages.userMessage(for: CKError(.permissionFailure) as NSError)
            == "You don't have permission for this. Check with the lead guide.")
        #expect(AppErrorMessages.userMessage(for: CKError(.serviceUnavailable) as NSError).hasPrefix(
            "iCloud is temporarily unavailable."))
    }

    @Test("A failed join never claims anything was saved")
    func joinMessages() {
        #expect(AppErrorMessages.joinMessage(for: CKError(.networkUnavailable))
            == "This device couldn't reach iCloud to join the classroom.")
        #expect(AppErrorMessages.joinMessage(for: CKError(.zoneNotFound))
            == "That invitation's classroom isn't available any longer.")
        #expect(AppErrorMessages.joinMessage(for: PlainError.boom) == "The classroom couldn't be joined.")
        for code in [CKError.Code.internalError, .notAuthenticated, .permissionFailure, .quotaExceeded] {
            #expect(!AppErrorMessages.joinMessage(for: CKError(code)).contains("saved"))
        }
    }

    // Bug hunt 2026-10-04: a join that failed offline arrived wrapped (a
    // partial failure holding each record's error, or a Core Data error over
    // CloudKit's) and read "The classroom couldn't be joined".
    @Test("A failed join is read from inside CloudKit's and Core Data's wrappers")
    func joinMessagesUnwrapped() {
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [
            "zone": CKError(.batchRequestFailed),
            "share": CKError(.networkFailure)
        ]])
        #expect(AppErrorMessages.joinMessage(for: partial)
            == "This device couldn't reach iCloud to join the classroom.")
        let coreData = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
            NSUnderlyingErrorKey: CKError(.notAuthenticated) as NSError
        ])
        #expect(AppErrorMessages.joinMessage(for: coreData) == "This device isn't signed in to iCloud.")
        let both = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
            NSUnderlyingErrorKey: partial as NSError
        ])
        #expect(AppErrorMessages.joinMessage(for: both) == "This device couldn't reach iCloud to join the classroom.")
        #expect(AppErrorMessages.sharingMessage(for: coreData, action: "leave the classroom")
            .hasPrefix("Couldn't leave the classroom. This device isn't signed in to iCloud."))
        // Nothing inside: as before.
        #expect(AppErrorMessages.joinMessage(for: CocoaError(.fileReadUnknown)) == "The classroom couldn't be joined.")
    }

    @Test("A failed sharing action names the action and never claims anything was saved")
    func sharingMessages() {
        #expect(AppErrorMessages.sharingMessage(for: CKError(.networkFailure), action: "add Sam")
            == "Couldn't add Sam. This device couldn't reach iCloud. Check you're online and try again.")
        #expect(AppErrorMessages.sharingMessage(for: CKError(.badContainer), action: "stop sharing")
            == "Couldn't stop sharing. iCloud didn't answer. Check you're online and try again.")
        #expect(AppErrorMessages.sharingMessage(for: SampleError(), action: "add Sam")
            == "The lesson file is missing a title row.")
        for code in [CKError.Code.internalError, .notAuthenticated, .permissionFailure, .quotaExceeded,
                     .unknownItem, .invalidArguments, .serverRejectedRequest] {
            let message = AppErrorMessages.sharingMessage(for: CKError(code), action: "add Sam")
            #expect(!message.contains("saved"))
            #expect(message.hasPrefix("Couldn't add Sam."))
            expectPlain(message)
        }
    }

    @Test("A pending invitation says to accept it first")
    func cloudKitParticipantAlreadyInvited() {
        let error = NSError(domain: "CKErrorDomain", code: 37)
        #expect(AppErrorMessages.userMessage(for: error, context: "joining the classroom")
            == "An invitation is already waiting to be accepted. Open the classroom link to accept it, then try again.")
    }

    @Test("File reads, writes, a full disk and Core Data validation each read differently")
    func cocoaCodes() {
        let readError = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        #expect(AppErrorMessages.userMessage(for: readError)
            == "There was a problem reading your notebook. Try closing and reopening the app.")

        let saveError = NSError(domain: NSCocoaErrorDomain, code: 1560) // NSValidationMultipleErrorsError
        #expect(AppErrorMessages.userMessage(for: saveError)
            == "Couldn't save your changes. Try again, or restart the app if it keeps happening.")

        let fullDisk = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        #expect(AppErrorMessages.userMessage(for: fullDisk)
            == "This device is out of space. Free some up and try again.")

        let noPermission = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(AppErrorMessages.userMessage(for: noPermission)
            == "Cosmic Daybook isn't allowed to save there. Try a different place.")
    }

    @Test("An unmapped error falls back to the general message with the activity")
    func unknownErrorFallsBack() {
        #expect(AppErrorMessages.userMessage(for: PlainError.boom, context: "syncing the calendar")
            == "Something went wrong while syncing the calendar. Try again.")
        #expect(AppErrorMessages.userMessage(for: PlainError.boom)
            == "Something went wrong while doing that. Try again.")
    }

    @Test("The Couldn't Save message never carries the caller's developer label")
    func saveFailureHasNoReason() {
        let message = AppErrorMessages.saveFailureMessage(for: NSError(domain: NSCocoaErrorDomain, code: 1560))
        #expect(message == "Couldn't save your changes. Try again, or restart the app if it keeps happening.")
        expectPlain(message)
    }

    @Test("A backup failure never shows raw text, a domain or a code")
    func backupMessages() {
        let raw = NSError(domain: "AutoBackupManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Backup already in progress"])
        #expect(AppErrorMessages.backupMessage(for: raw, operation: "back up your notebook")
            == "Couldn't back up your notebook. Try again.")
        #expect(AppErrorMessages.backupMessage(for: SampleError(), operation: "restore your backup")
            == "The lesson file is missing a title row.")
        let fullDisk = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        #expect(AppErrorMessages.backupMessage(for: fullDisk, operation: "save the backup")
            == "There isn't enough space to save the backup. Free up space and try again.")
        for error in [raw, fullDisk, NSError(domain: NSCocoaErrorDomain, code: 4242)] {
            expectPlain(AppErrorMessages.backupMessage(for: error, operation: "save the backup"))
        }
    }

    @Test("A file that can't be added says why in plain words")
    func importMessages() {
        let missing = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        #expect(AppErrorMessages.importMessage(for: missing, fileType: "PDF")
            == "Couldn't find the PDF. It may have been moved or deleted.")
        let fullDisk = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        #expect(AppErrorMessages.importMessage(for: fullDisk, fileType: "PDF")
            == "There isn't enough space to add this PDF. Free up some space and try again.")
        #expect(AppErrorMessages.importMessage(for: PlainError.boom, fileType: "PDF")
            == "Couldn't add the PDF. Make sure it's the right kind of file and try again.")
    }

    @Test("An Apple Intelligence failure is plain, and an app error isn't blamed on Apple Intelligence")
    func aiMessages() {
        #expect(AppErrorMessages.aiMessage(for: LocalModelError.rateLimited) == AppleIntelligenceMessages.busy)
        #expect(AppErrorMessages.aiMessage(for: LocalModelError.contextTooLarge) == AppleIntelligenceMessages.tooLong)
        #expect(AppErrorMessages.aiMessage(for: LocalModelError.invalidJSON) == AppleIntelligenceMessages.unreadable)
        #expect(AppErrorMessages.aiMessage(for: LocalModelError.unavailable(""))
            == AppleIntelligenceMessages.notAvailable)
        #expect(AppErrorMessages.aiMessage(for: LocalModelError.unavailable(AppleIntelligenceMessages.turnOn))
            == AppleIntelligenceMessages.turnOn)
        #expect(AppErrorMessages.aiMessage(for: SampleError()) == "The lesson file is missing a title row.")
        #expect(AppErrorMessages.aiMessage(for: PlainError.boom, fallback: "Couldn't make a plan. Try again.")
            == "Couldn't make a plan. Try again.")
        let rawText = "The data couldn't be read because it isn't in the correct format."
        let decoding = NSError(domain: NSCocoaErrorDomain, code: 4864, userInfo: [NSLocalizedDescriptionKey: rawText])
        #expect(AppErrorMessages.aiMessage(for: decoding) == AppleIntelligenceMessages.fallback)
        for error: Error in [LocalModelError.rateLimited, LocalModelError.invalidJSON, decoding, PlainError.boom] {
            let message = AppErrorMessages.aiMessage(for: error)
            #expect(!message.hasPrefix("Generation failed"))
            #expect(!message.contains("AI feature"))
            expectPlain(message)
        }
    }
}
