import Foundation
import CloudKit
import Testing
@testable import CosmicDaybook

/// Pins the user-facing strings `AppErrorMessages.userMessage` produces for one
/// representative input per branch, so the per-domain helpers stay a pure
/// refactor of the switch they were split out of.
@MainActor
@Suite("App error messages")
struct AppErrorMessagesTests {

    private struct SampleError: LocalizedError {
        var errorDescription: String? { "The lesson file is missing a title row." }
    }

    /// Not a `LocalizedError`, so nothing can speak for it and the domain
    /// switch has to fall through to its default.
    private enum PlainError: Error { case boom }

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
            == "Your iCloud storage is full. Free up space so your data can continue syncing.")
    }

    @Test("CloudKit codes read as what they are: signed out, offline, a gone zone")
    func cloudKitCodesMatchTheirNames() {
        #expect(AppErrorMessages.userMessage(for: CKError(.notAuthenticated) as NSError)
            == "No iCloud account found. Sign in to iCloud in Settings to sync your data.")
        #expect(AppErrorMessages.userMessage(for: CKError(.networkFailure) as NSError, context: "joining")
            == "Couldn't reach iCloud while joining. Your changes are saved locally.")
        #expect(AppErrorMessages.userMessage(for: CKError(.zoneNotFound) as NSError)
            == "The shared classroom data isn't available yet. Ask the lead guide to re-share.")
        #expect(AppErrorMessages.userMessage(for: CKError(.permissionFailure) as NSError)
            == "You don't have permission for this action. Check with the lead guide.")
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
            #expect(!AppErrorMessages.joinMessage(for: CKError(code)).contains("saved locally"))
        }
    }

    @Test("A pending invitation says to accept it first")
    func cloudKitParticipantAlreadyInvited() {
        let error = NSError(domain: "CKErrorDomain", code: 37)
        #expect(AppErrorMessages.userMessage(for: error, context: "joining the classroom")
            == "An invitation is already waiting to be accepted. Open the classroom link to accept it, then try again.")
    }

    @Test("A Core Data read error and a save error read differently")
    func coreDataCodes() {
        let readError = NSError(domain: NSCocoaErrorDomain, code: 260)
        #expect(AppErrorMessages.userMessage(for: readError)
            == "There was a problem reading your data. Try closing and reopening the app.")

        let saveError = NSError(domain: NSCocoaErrorDomain, code: 1560)
        #expect(AppErrorMessages.userMessage(for: saveError)
            == "Couldn't save your changes. Try again, or restart the app if the problem persists.")
    }

    @Test("An unmapped error falls back to the generic message with the activity")
    func unknownErrorFallsBack() {
        #expect(AppErrorMessages.userMessage(for: PlainError.boom, context: "syncing the calendar")
            == "An unexpected issue occurred while syncing the calendar. Try again.")
        #expect(AppErrorMessages.userMessage(for: PlainError.boom)
            == "An unexpected issue occurred while completing this action. Try again.")
    }
}
