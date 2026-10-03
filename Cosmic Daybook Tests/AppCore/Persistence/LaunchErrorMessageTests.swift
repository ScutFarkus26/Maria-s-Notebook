import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - Opening the notebook, in plain English
//
// When the notebook won't open, the error screen and the banners say so in
// everyday words. Store file names, database format numbers, error domains
// and codes are kept for the log and the screen's Details disclosure.

@Suite("Launch errors: plain-English messages")
@MainActor
struct LaunchErrorMessageTests {

    private let underlying = NSError(domain: NSCocoaErrorDomain, code: 134_110, userInfo: [
        NSLocalizedDescriptionKey: "An error occurred during persistent store migration."
    ])

    private var stackErrors: [CoreDataStackError] {
        [
            .modelNotFound("CosmicDaybook"),
            .storeLoadFailed(underlying),
            .cloudKitLoadFailed(underlying),
            .storeFromNewerBuild(storeName: "private.sqlite", storeVersion: 15, appVersion: 14),
            .storeSchemaIncoherent(storeName: "private.sqlite", detail: "ZSTUDENT.ZLEFTAT")
        ]
    }

    @Test("A stack error's message names no file, format number, domain or code; its detail does")
    func stackErrorsArePlain() throws {
        for error in stackErrors {
            let message = try #require(error.errorDescription)
            for marker in ["sqlite", "15", "14", "NSCocoaErrorDomain", "134110", "ZSTUDENT", "Core Data",
                           "persistent store", "Settings \u{2192} Database", "Reset Local Cache"] {
                #expect(!message.contains(marker), "\"\(message)\" contains \(marker)")
            }
        }
        let newer = CoreDataStackError.storeFromNewerBuild(
            storeName: "private.sqlite", storeVersion: 15, appVersion: 14
        )
        #expect(newer.technicalDetail.contains("private.sqlite"))
        #expect(newer.technicalDetail.contains("15"))
        #expect(CoreDataStackError.storeLoadFailed(underlying).technicalDetail.contains("NSCocoaErrorDomain 134110"))
    }

    @Test("A damaged store points at the re-download button by its real name")
    func damagedStoreNamesTheButton() {
        let message = CoreDataStackError.storeSchemaIncoherent(storeName: "private.sqlite", detail: "x")
            .errorDescription ?? ""
        #expect(message.contains("\u{201C}Re-download from iCloud\u{2026}\u{201D}"))
    }

    @Test("The error screen speaks plainly for a stack error, an app sentence, and raw system text")
    func errorScreenMessage() {
        #expect(DatabaseErrorCoordinator.userMessage(for: CoreDataStackError.storeLoadFailed(underlying))
            == "Cosmic Daybook couldn't open your notebook.")
        // A CloudKit store reaches the screen only when it can't be opened at all.
        #expect(DatabaseErrorCoordinator.userMessage(for: CoreDataStackError.cloudKitLoadFailed(underlying))
            == "Cosmic Daybook couldn't open your notebook.")
        let wrapped = NSError(domain: "CosmicDaybook", code: 6000, userInfo: [
            NSLocalizedDescriptionKey: "This copy of Cosmic Daybook is damaged. Reinstall it."
        ])
        #expect(DatabaseErrorCoordinator.userMessage(for: wrapped)
            == "This copy of Cosmic Daybook is damaged. Reinstall it.")
        #expect(DatabaseErrorCoordinator.userMessage(for: underlying) == DatabaseErrorCoordinator.genericMessage)
    }

    @Test("The raw description keeps the stack error's facts, or the system text with its domain and code")
    func technicalDescription() {
        #expect(DatabaseErrorCoordinator.technicalDescription(of: underlying)
            == "An error occurred during persistent store migration. (NSCocoaErrorDomain 134110)")
        let newer = CoreDataStackError.storeFromNewerBuild(storeName: "shared.sqlite", storeVersion: 15, appVersion: 14)
        #expect(DatabaseErrorCoordinator.technicalDescription(of: newer) == newer.technicalDetail)
    }

    @Test("Marking an in-memory session sets the flag the safe-mode banner reads, and the older flag with it")
    func inMemorySessionFlag() {
        let defaults = UserDefaults.standard
        let keys = [UserDefaultsKeys.inMemoryStoreSession, UserDefaultsKeys.ephemeralSessionFlag]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }

        DatabaseInitializationService.markInMemorySession(true)
        #expect(defaults.bool(forKey: UserDefaultsKeys.inMemoryStoreSession))
        #expect(defaults.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag))
        DatabaseInitializationService.markInMemorySession(false)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.inMemoryStoreSession))
        #expect(!defaults.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag))
    }
}
