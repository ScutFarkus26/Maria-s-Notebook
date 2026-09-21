import Foundation
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
        let error = NSError(domain: "CKErrorDomain", code: 9)
        #expect(AppErrorMessages.userMessage(for: error)
            == "Your iCloud storage is full. Free up space so your data can continue syncing.")
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
